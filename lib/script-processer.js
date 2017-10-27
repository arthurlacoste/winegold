const {app} = require('electron');
const yaml = require('js-yaml');
const Data = require('electron-store');
const path = require('path');
const fs = require('fs-extra');

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
	if (element.indexOf(compare) === -1) {
		element.push(compare);
	}
	return element;
};

const evalDeep = function (js, script) {
	const {forkString} = require('child-process-fork-string');

  // With silent: true, you can see and use stdout/stderr
	const exec = forkString(js, {silent: true});

	exec.stdout.on('data', data => {
		console.log(data);
		Object.assign(script, {data});
		ipcEvent.sender.send('add-process-out', script);
	});

	exec.stderr.on('data', data => {
		console.log(data);
		Object.assign(script, {data: `${data}`});
		ipcEvent.sender.send('add-process-out', script);
		ipcEvent.sender.send('process-err', script);
	});

	exec.on('close', code => {
		if (code === 0) {
			ipcEvent.sender.send('process-finished', script);
		} else {
			ipcEvent.sender.send('process-err', script);
		}
	});
};

// Executer a shell command
const execute = function (cmd, script, ending = false) {
	const {spawn} = require('child_process');

	const exec = spawn(cmd, [], {shell: true});

	exec.stdout.on('data', data => {
		if (script.execInWindow === true) {
			Object.assign(script, {data});
			console.log(`${script.data}`);
			ipcEvent.sender.send('add-process-out', script);
      // Cmd = `"${cmd.replace(/'/g, `'\\''`)}"`;
      // cmd = `osascript -e 'tell app "Terminal"' -e 'do script ${cmd}' -e 'end tell'`
		}
	});

	exec.stderr.on('data', data => {
		if (script.execInWindow === true) {
			Object.assign(script, {data});
			ipcEvent.sender.send('add-process-out', script);
			ipcEvent.sender.send('process-err', script);
		}
	});

	exec.on('close', code => {
		console.log('command END ' + code);

      // If cmd is in after, this launch it on background
		if (ending === true) {
			console.log('END');
			ipcEvent.sender.send('process-finished', script);
		}
	});
};

// Parse all yml scripts, return object
module.exports.getAllscripts = function () {
	allScripts = [];
	list.forEach(f => {
    // Console.log(path.resolve(f))
		if (!path.isAbsolute(f)) {
			f = path.join(app.getAppPath() + '/' + f);
			console.log(f);
		}
		try {
			const doc = yaml.safeLoad(fs.readFileSync(f, 'utf8'));
			allScripts.push(doc);
      // Console.log(doc)
		} catch (err) {
			console.log(err);
		}
	});

  // Console.log(allScripts);
	return allScripts;
};

/*
 * Verify and add a script file if he respect format
 * file: complete file with path
 * return: true if script was added
 */
const addScript = function (file) {
  // Test YAML integrity
  // script.cmd.exec = script.cmd.exec.replace("<filename>",  file)
  // console.log(script.cmd.exec)
	try {
		const doc = yaml.safeLoad(fs.readFileSync(file, 'utf8'));

    // Test presence of triggers and command
		console.log(typeof (doc.trigger));

		console.log(typeof (doc.cmd));

    // If correct
		data.set('list', pushIfNotExist(list, file));
		return true;
	} catch (err) {
		console.log(err);
	}
};

launchScript = function (file, script) {
	Object.assign(script, {file});
  // Console.log(script)
	if (typeof (script.trigger.fileExtension) === 'string') {
		if (file.indexOf(script.trigger.fileExtension) === -1) {
			return false;
		}
	}
	file = `'${file.replace(/'/g, `'\\''`)}'`;
	try {
		if (typeof (script.cmd.exec) !== 'undefined') {
			script.cmd.exec = script.cmd.exec.replace('<input>', file);
			script.cmd.exec = script.cmd.exec.replace('<output>', file);
      // Console.log("verifier " + script.cmd.exec)
			execute(script.cmd.exec, script, true);
		}

		if (typeof (script.cmd.eval) !== 'undefined') {
			script.cmd.eval = script.cmd.eval.replace('<filename>', file);
			evalDeep(script.cmd.eval, script);
		}

		if (typeof (script.cmd.internal) !== 'undefined' && script.cmd.internal === 'addScript') {
			addScript(script.file);
		}

		if (typeof (script.after.exec) !== 'undefined') {
			script.after.exec = script.after.exec.replace('<input>', file);
			script.after.exec = script.after.exec.replace('<output>', file);
			execute(script.after.exec, script);
		}

		if (typeof (script.after.eval) !== 'undefined') {
			ipcEvent.sender.send('eval-browser', script.after.eval);
		}
	} catch (err) {
		console.log(err);
	}
};

/*
 * ParseAllScripts for one file
 *
 */
module.exports.parseAllScripts = function (file) {
	const scriptsforThisFile = [];
	this.getAllscripts();
	allScripts.forEach(s => {
    // Console.log(typeof(s.trigger.fileExtension))
		if (typeof (s.trigger.fileExtension) === 'string' && file.indexOf(s.trigger.fileExtension) !== -1) {
			scriptsforThisFile.push(s);
			if (s.autolaunch === true) {
				launchScript(file, s);
			}
		} else if (typeof (s.trigger.fileExtension) === 'object') {
			s.trigger.fileExtension.some(ext => {
				if (file.indexOf(ext) !== -1) {
					console.log(ext + ' found');
					scriptsforThisFile.push(s);
					if (s.autolaunch === true) {
						launchScript(file, s);
					}
					return false;
				}
			});
		}
	});
	if (scriptsforThisFile.length === 0) {
		console.log('rien');
		ipcEvent.sender.send('process-err', {file});
	}
	console.log(scriptsforThisFile);
};

// Construct
module.exports.init = function (ipcMain) {
	const configFiles = ['scripts/config.add.yml', 'scripts/pdf.add.yml'];
	if (data.get('list') === undefined) {
		data.set('list', configFiles);
	}
	data.set('list', configFiles);

	list = data.get('list');

  // Import ipcMain object
	ipcEvent = ipcMain;

	list.forEach(f => {
		console.log('trying : ' + app.getPath('userData') + '/' + f);
		fs.exists(app.getPath('userData') + '/' + f, exists => {
			if (!exists) {
				fs.copy(app.getAppPath() + '/' + f, app.getPath('userData') + '/' + f, err => {
					if (err) {
						console.error(err);
					} else {
						console.log('success: ' + app.getPath('userData') + '/' + f);
					}
				});
			}
		});
	});
};
