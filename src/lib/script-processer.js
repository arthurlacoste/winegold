const {app, ipcMain} = require('electron');
const path = require('path');
const Data = require('electron-store');
const fs = require('fs-extra');
const isDev = require('electron-is-dev');
const id = require('id.log');
const tampax = require('tampax');
const async = require('async');
const mem = require('mem');
const junk = require('junk');
const kill = require('tree-kill');
const pify = require('pify');
const words = require('./words-to-replace');

id.isDev(isDev);
let ipcEvent;
const data = new Data();
let allScripts = [];

// The first script => create config file for core scripts
const addScriptConfig = {name: 'Add Winegold script',
	trigger: {fileExtension: 'add.yml'},
	cmd: {internal: 'addScript'},
	after: {exec: 'echo "Script ajouté !"'},
	autolaunch: true,
	scriptId: 0};

let list;
let scriptPath;
let token = Date.now();

/*
 * Elephant promisify a callback function & memorize
 * it during 3sec. Powerful but... Tokens are more simple.
 */
const elephant = mem(pify, {maxAge: 3000});

const outData = function (cmd, s) {
	console.log(s);
	ipcEvent.sender.send(cmd, s);
};

/*
 * OutShell send one or more ipcEvent to the renderer process
 * s: script Object
 * data: message to send to shell
 * args: object of argument for others ipc events
 */
const outShell = function (s, data, args) {
	if (args !== null) {
		Object.assign(s, args);
	}
	args = args || {};
	Object.assign(s, {data: `${data}\n`});

	ipcEvent.sender.send('add-process-out', s);
	if (args.err) {
		ipcEvent.sender.send('process-err', s);
	}
	if (args.finished) {
		ipcEvent.sender.send('process-finished', s);
	}
};

const getScriptPath = function (cb) {
	const sp = data.get('scriptPath');

  // Create path if he desn't exists
	fs.exists(sp, exists => {
		if (!exists) {
			fs.mkdir(sp, err => {
				outData('log', err);
			});
		}
		if (sp === undefined) {
			data.set('scriptPath', path.join(app.getPath('userData'), 'scripts'));
			return cb(null, path.join(app.getPath('userData'), 'scripts'));
		}
		return cb(null, sp);
	});
};

/*
 * Executer a shell command
 * cmd: command to Execute
 * s: script Object
 * type: js or shell
 * ending: false by default
 */
const execute = async.queue((args, callback) => {
	let cmd = args.cmd;
	const s = args.s;
	const ending = args.ending;
	const idFile = args.idFile;

  /*
   * Replace words in script, and read the content of the file to add {{inside}}
   * More on ./words-to-replace & https://github.com/arthurlacoste/tampax
   */
	words(cmd, s, (err, data) => {
		if (err) {
			outShell(s, `${err}`);
		}

		cmd = data;
		outShell(s, `Starting script ${cmd}`);
		let exec;
		if (args.type === 'js') {
			const {forkString} = require('child-process-fork-string');
			exec = forkString(cmd, {silent: true});
		} else {
			const spawn = require('execa');
			exec = spawn(cmd, [], {shell: true, encoding: 'ucs2'});
		}

		ipcMain.on('cancel', () => {
			kill(exec.pid, 'SIGKILL', err => {
				if (err) {
					outShell(s, `${err}`, {idFile});
					return;
				}
				outShell(s, `${exec.pid} over.`);
			});
		});

		if (s.execInWindow === true) {
			outData('open-shell', s);
		}

		exec.stdout.on('data', data => {
			outShell(s, `✅  ${data}`, {idFile});
		});

		exec.stderr.on('data', data => {
			outShell(s, `⚠️  ${data}`, {err: true, idFile});
		});

		exec.on('close', code => {
			if (code === 0 || ending) {
				outData('process-finished', s);
				callback();
			} else {
				callback('Error !');
			}

      // If cmd is after, launch this on background
			if (ending === true) {
				outData('process-finished', s);
			}
		});
	});
});

// Parse all yml scripts, return object with all scripts
const getAllscripts = function (cb) {
	if (token <= Date.now())	{
		allScripts = [];
		allScripts.push(addScriptConfig);
		let scriptId = 1;
		if (list.length === 0) {
			return cb();
		}
		list.forEach((f, index) => {
			f = path.join(scriptPath, f);
			console.log('F', f);

			fs.readFile(f, 'utf8', (err, data) => {
				if (err) return outData('log', err);
				tampax.yamlParseString(data, (err, doc) => {
					if (err) {
						outData('log', err);
					} else {
						if (!doc.name) {
							if (doc.cmd.exec) {
								doc.name = doc.cmd.exec.substring(0, 8);
							} else if (doc.cmd.eval) {
								doc.name = doc.cmd.eval.substring(0, 8);
							}
						}

						Object.assign(doc, {scriptFile: f, scriptId});
						allScripts.push(doc);

						scriptId += 1;
					}
					if (index === list.length - 1) {
						return cb();
					}
				});
			});
		});
	} else {
		return cb();
	}
};

/*
 * Verify and add a script file if he respect format
 * file: complete file with path
 * return: true if script was added
 * FILE.ADD.YML
 */
const addScript = function (file) {
  // Test YAML integrity
	fs.readFile(file, 'utf8', (err, data) => {
		if (err) return outShell({file}, err, {err: true});
		tampax.readYamlString(data, (err, doc) => {
			if (err) return outShell({file}, err, {err: true});
      // Test presence of triggers and command
			if (doc.trigger && doc.cmd) {
        // Copy file to userData
				const basename = path.basename(file);
				const newFile = path.join(app.getPath('userData'), 'scripts', basename);

				fs.copy(file, newFile, err => {
					if (err) {
						outShell({file}, err, {err: true});
					} else {
						const mess = 'File moved to ' + newFile;
						outShell({file}, mess);
					}
				});
				return true;
			}
			const mess = 'Have you a correct trigger & cmd ?';
			outShell({file}, mess, {err: true});

    // If correct
		});
	});
};

/*
 * LaunchScript try to execute all the before, cmd & after commands
 * file: file path+name
 * s: script Object
 */
const launchScript = function (args, s) {
	const idFile = args.idFile;
  // Need to refresh script after launch, if he is edited between time ?
	const fileFormated = `'${args.file.replace(/'/g, `'\\''`)}'`;
	Object.assign(s, {file: args.file, fileFormated});

	const si = Object.assign({}, s, idFile);

	try {
		if (s.before) {
			if (s.before.exec) {
				execute.push({cmd: s.before.exec, s, type: 'shell', ending: false, idFile});
			}
			if (s.before.eval) {
				outData('eval-browser', s.before.eval);
			}
		}

    // True = send ending process
		if (s.cmd.exec) {
			execute.push({cmd: s.cmd.exec, s, type: 'shell', ending: true, idFile});
		}
		if (s.cmd.eval) {
			execute.push({cmd: s.cmd.eval, s, type: 'js', ending: true, idFile});
		}

    // Internal command
		if (s.cmd.internal === 'addScript') {
			addScript(s.file);
		}

		if (s.after) {
			if (s.after.exec) {
				execute.push({cmd: s.after.exec, s, type: 'shell', ending: false, idFile});
			}

			execute.drain = function () {
				if (s.after.eval) {
					const cmd = s.after.eval;
					words(cmd, s, (err, data) => {
						if (err) {
							outShell(s, `${err}`);
						}
						outData('eval-browser', data);
					});
				}
			};
		}
	} catch (err) {
		outShell(si, err, true);
	}
};

/*
 * ParseAllScripts for one file
 * Search file extension in all script
 * if he found a match => launchScript()
 * file: a file
 * start: when autolaunch=false, select your script and click to process
 */
const parseAllScripts = function (args) {
	console.log('PARSE FOR', args.name);
	const idFile = args.idFile;
	const file = args.path;
	const scriptsforThisFile = [];

	if (allScripts.length > 0) {
		allScripts.forEach(s => {
			if (typeof (s.trigger.fileExtension) === 'string' &&
  file.indexOf(s.trigger.fileExtension) !== -1) {
				scriptsforThisFile.push(s);
				if (s.autolaunch === true) {
					outData('log', `${args.idFile}: Launching '${s.name}'...`);
					launchScript({file, idFile}, s);
				}
			} else if (typeof (s.trigger.fileExtension) === 'object') {
				s.trigger.fileExtension.forEach(ext => {
					if (file.indexOf(ext) !== -1) {
						scriptsforThisFile.push(s);
						if (s.autolaunch === true) {
							outData('log', `${args.idFile}: Launching '${s.name}'...`);
							launchScript({file, idFile}, s);
						}
					}
				});
			}
		});
	}

	if (scriptsforThisFile.length === 0) {
		outShell(args, `No scripts found for '${args.name}' (id ${args.idFile}). Create you own !`, {err: true});
	} else {
		const autolaunch = scriptsforThisFile[0].autolaunch;
		const scriptsAndFile = {
			scripts: scriptsforThisFile,
			file,
			idFile};

		outData('add-scripts', scriptsAndFile);

		if (!autolaunch || autolaunch === false) {
			outData('icon-pause', {idFile});
			outShell({idFile}, `Waiting for a script to choose (process column) (id ${args.idFile}).`);
		}
	}
};

const getListScript = function (cb) {
	if (token <= Date.now())	{
		list = [];
		fs.readdir(scriptPath, (err, files) => {
			if (err) {
				outData('log', err);
				return cb(err);
			}

			if (files.length === 0) {
				return cb();
			}
			files = files.filter(junk.not);

			files.forEach(file => {
				list.push(file);
				if (list.length === files.length) {
					return cb();
				}
			});
		});
	} else {
		return cb();
	}
};

/*
Const initExist = function (p, f) {
	fs.exists(p, exists => {
		if (!exists) {
			fs.copy(path.join(app.getAppPath(), f), p, err => {
				if (err) {
					outData('log', err);
					console.error(err);
				} else {
					outData('log', 'No err');
				}
			});
		}
	});
};
*/
/*
 * Main processor, launch when a file is dropped
 * he is launch from a main ipc receiver from renderer
 */
const processScript = function (ipcMain, args) {
	ipcEvent = ipcMain;

	elephant(getScriptPath)().then(path => {
		scriptPath = path;
    // List all scripts
		getListScript(err => {
			if (err) {
				outData('log', `${err}`);
			}
      // Then, get all scripts
			getAllscripts(err => {
				if (err) {
					outData('log', `${err}`);
				}
        // Adding time to memorize all the data for future files (=3sec)
				if (token <= Date.now())	{
					token = Date.now() + 3000;
				}
        // Finally, add script to renderer or process
				if (args.noParseFile !== true) {
					parseAllScripts(args);
				}
			});
		});
	}).catch(err => {
		outData('log', `${err}`);
	});
};

// Construct
const init = function (ipcMain) {
  // Create scripts
	processScript(ipcMain, {noParseFile: true});
};

module.exports = init;
module.exports.processScript = processScript;
module.exports.parseAllScripts = parseAllScripts;
module.exports.launchScript = launchScript;
module.exports.getAllscripts = getAllscripts;
module.exports.execute = execute;
