const {app, ipcMain} = require('electron');
const path = require('path');
const Data = require('electron-store');
const yaml = require('js-yaml');
const fs = require('fs-extra');
const isDev = require('electron-is-dev');
const id = require('id.log');
const tampax = require('tampax');
const async = require('async');

const kill = require('tree-kill');
const words = require('./words-to-replace');

id.isDev(isDev);
let ipcEvent;
const data = new Data();
let allScripts = {};
let list;

/*
 * PushIfNotExist() push an element if is not
 * already exist in the array
 * element: Array object
 * compare: string to add
 * return:  array
 */
const pushIfNotExist = function (element, compare) {
	if (element.indexOf(compare) === -1)		{
		element.push(compare);
	}

	return element;
};

/*
 * OutShell send one or more ipcEvent to the renderer process
 * s: script Object
 * data: message to send to shell
 * args: object of argument for others ipc events
 */
const outShell = function (s, data, args) {
	args = args || {};
	console.log(data);
	Object.assign(s, {data: `${data}\n`});
	ipcEvent.sender.send('add-process-out', s);
	if (args.err) {
		ipcEvent.sender.send('process-err', s);
	}
	if (args.finished) {
		ipcEvent.sender.send('process-finished', s);
	}
};

const outData = function (cmd, s) {
	ipcEvent.sender.send(cmd, s);
};

/*
 * Executer a shell command
 * cmd: command to Execute
 * s: script Object
 * type: js or shell
 * ending: false by default
 */
const execute = async.queue((args, callback) => {
	console.log(args);
	let cmd = args.cmd;
	const s = args.s;
	const ending = args.ending;

	// Cmd = cmd.replace(/<file>/g, s.fileFormated);
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
			console.log('js detected');
		} else {
			const {spawn} = require('child_process');
			exec = spawn(cmd, [], {shell: true, encoding: 'ucs2'});
		}

		ipcMain.on('cancel', () => {
			console.log(`Terminate ${exec.pid}`);
			kill(exec.pid, 'SIGKILL', err => {
				if (err) {
					outShell(s, `${err}`);
					return;
				}
				outShell(s, `${exec.pid} over.`);
			});
		});

		if (s.execInWindow === true) {
			outData('open-shell', s);
		}

		exec.stdout.on('data', data => {
			console.log(data);

			outShell(s, `✅  ${data}`);
		});

		exec.stderr.on('data', data => {
			outShell(s, `⚠️  ${data}`, {err: true});
		});

		exec.on('close', code => {
			console.log('command END ' + code);
			if (code === 0 || ending)			{
				outData('process-finished', s);
				callback();
			}		else {
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
module.exports.getAllscripts = function () {
	allScripts = [];
	let scriptId = 0;
	list.forEach(f => {
		f = path.join(app.getPath('userData'), f);

		// Console.log(f);
		try {
			const doc = tampax.yamlParseString(fs.readFileSync(f, 'utf8'));

			if (!doc.name) {
				if (doc.cmd.exec) {
					doc.name = doc.cmd.exec.substring(0, 8);
				} else if (doc.cmd.eval) {
					doc.name = doc.cmd.eval.substring(0, 8);
				}
			}

			Object.assign(doc, {scriptFile: f, scriptId});
			allScripts.push(doc);
			console.log(doc);
			scriptId += 1;
		} catch (err) {
			console.log(err);
		}
	});

	return allScripts;
};

/*
 * Verify and add a script file if he respect format
 * file: complete file with path
 * return: true if script was added
 */
const addScript = function (file) {
  // Test YAML integrity
	try {
		const doc = yaml.safeLoad(fs.readFileSync(file, 'utf8'));

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

			const newfileRelative = path.join('scripts', basename);
			// Add to config file
			data.set('list', pushIfNotExist(list, newfileRelative));
			return true;
		}
		const mess = 'Have you a correct trigger & cmd ?';
		outShell({file}, mess, {err: true});

    // If correct
	} catch (err) {
		outShell({file}, err, {err: true});
	}
};

/*
 * LaunchScript try to execute all the before, cmd & after commands
 * s: script Object
 */
const launchScript = function (file, s) {
	console.log('start LS');
	const fileFormated = `'${file.replace(/'/g, `'\\''`)}'`;
	Object.assign(s, {file, fileFormated});
  // Console.log(s)
	const queueArgs = {
		cmd: '',
		s,
		type: 'shell',
		ending: false
	};

	try {
		if (s.before) {
			if (s.before.exec) {
				execute.push({cmd: s.before.exec, s, type: 'shell', ending: false});
			}
			if (s.before.eval) {
				outData('eval-browser', s.before.eval);
			}
		}

		// True = send ending process
		if (s.cmd.exec) {
			execute.push({cmd: s.cmd.exec, s, type: 'shell', ending: true});
		}
		if (s.cmd.eval) {
			execute.push({cmd: s.cmd.eval, s, type: 'js', ending: true});
		}

		// Internal command
		if (s.cmd.internal === 'addScript') {
			addScript(s.file);
		}

		if (s.after) {
			if (s.after.exec) {
				queueArgs.cmd = s.after.exec;
				execute.push({cmd: s.after.exec, s, type: 'shell', ending: false});
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
		outShell(s, err, true);
	}
};

/*
 * ParseAllScripts for one file
 * Search file extension in all script
 * if he found a match => launchScript()
 * file: a file
 * start: when autolaunch=false, select your script and click to process
 */
module.exports.parseAllScripts = function (args) {
	const idFile = args.idFile;
	const file = args.path;
	const scriptsforThisFile = [];
	this.getAllscripts();

	console.log(allScripts);

	allScripts.forEach(s => {
		s.idFile = idFile;
    // Console.log(typeof(s.trigger.fileExtension))
		if (typeof (s.trigger.fileExtension) === 'string' &&
		file.indexOf(s.trigger.fileExtension) !== -1) {
			scriptsforThisFile.push(s);
			if (s.autolaunch === true) {
				launchScript(file, s);
			}
		} else if (typeof (s.trigger.fileExtension) === 'object') {
			s.trigger.fileExtension.forEach(ext => {
				console.log(ext);
				if (file.indexOf(ext) !== -1) {
					scriptsforThisFile.push(s);
					if (s.autolaunch === true) {
						launchScript(file, s);
					}

					return false;
				}
				return true;
			});
		}
	});

	if (scriptsforThisFile.length === 0) {
		outShell(args, 'No scripts found for this file. Create you own !', {err: true});
	} else {
		const autolaunch = scriptsforThisFile[0].autolaunch;
		if (!autolaunch || autolaunch === false) {
			const scriptsAndFile = {
				scripts: scriptsforThisFile,
				file,
				idFile
			};
			outShell(scriptsAndFile, 'Waiting for a script to choose (process column).');
			outData('add-scripts', scriptsAndFile);
		}
	}
	console.log(scriptsforThisFile);
};

// Construct
module.exports.init = function (ipcMain) {
	const configFiles = ['scripts/config.add.yml', 'scripts/pdf.add.yml'];
	if (data.get('list') === undefined)	{
		data.set('list', configFiles);
	}

	// If (isDev) data.set('list', configFiles);

	list = data.get('list');

	id({id: 'goodid'});
	id.log(data.get('list'));
  // Import ipcMain object
	ipcEvent = ipcMain;

	// Copy all files stored in a library userData
	list.forEach(f => {
		const p = path.join(app.getPath('userData'), f);
		console.log(p);
		fs.exists(p, exists => {
			if (!exists) {
				fs.copy(path.join(app.getAppPath(), f), p, err => {
					if (err) {
						console.error(err);
					} else {
						console.log('success: ' + p);
					}
				});
			}
		});
	});
};

module.exports.launchScript = launchScript;
module.exports.execute = execute;
