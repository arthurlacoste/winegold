const {app, BrowserWindow} = require('electron');
const path = require('path');
const isDev = require('electron-is-dev');

const __base = path.join(__dirname, '/');

if (isDev) {
	require('electron-reload')(__dirname);
}
/*
Var test = false
if(process.argv[2]==='-t') { test = true }

console.log(test) */

const url = require('url');
const fs = require('fs');
const Config = require('electron-store');

const config = new Config();
// Const scriptsList = new Config({default: })
const ipc = require('electron').ipcMain;
const id = require('id.log');

id.log(config.get('scriptsList'));
// Reception of an url
ipc.on('url-reception', function urlReception(event, args) {
	console.log(args.path);

  // Console.log(scripts);

	const recognizedExtention = true;

  // Get informations about the file
	fs.stat(args.path, (err, stats) => {
		if (err) {
			console.log(err);
			return;
		}
		if (stats.isDirectory()) {
			fs.readdir(args.path, (err, files) => {
				if (err) {
					console.log(err);
					return;
				}
				files.forEach(file => {
					const fileInfo = {
						path: args.path + '/' + file,
						name: file
					};

          // Search files recursively
					urlReception(event, fileInfo);
				});
			});
		} else if (recognizedExtention === true) {
			const list = {};

      // Merging data from all sources
			Object.assign(list, stats, args);

      // Sending element to main list
			event.sender.send('element-ok', list);
		} else {
      // Element pas ok

      // deja dans la liste, etc
		}
	});
});

ipc.on('start-script', (event, args) => {
  // Test if element is allowed
	const sp = require(__base + 'lib/script-processer.js');
	sp.init(event);
	sp.parseAllScripts(args.path);
});

// Keep a global reference of the window object, if you don't, the window will
// be closed automatically when the JavaScript object is garbage collected.

let win;

// This method will be called when Electron has finished
// initialization and is ready to create browser windows.
// Some APIs can only be used after this event occurs.

app.on('ready', () => {
	const optsInit = {
		minHeight: 340,
		minWidth: 300,
		show: false,
		icon: 'icons/mac/icon.icns'
	};
	const opts = {};
	Object.assign(opts, config.get('winBounds'), optsInit);
	console.log(opts);
	win = new BrowserWindow(config.get('winBounds'));
	win.loadURL(url.format({
		pathname: path.join(__dirname, 'index.html'), //
    // pathname: path.join(__dirname, 'assets/list.html'),
		protocol: 'file:',
		slashes: true
	}));

	win.once('ready-to-show', win.show);
	win.setMinimumSize(320, 300);

	if (isDev) {
		win.webContents.openDevTools();
	}
  // Save window size and position
	win.on('close', () => {
		console.log(win.getBounds());
		config.set('winBounds', win.getBounds());
	});

	win.on('move', () => {
		console.log(win.getBounds());
		config.set('winBounds', win.getBounds());
	});

  // Emitted when the window is closed.
	win.on('closed', () => {
		win = null;
	});
});

// Quit when all windows are closed.
app.on('window-all-closed', () => {
	app.quit();
});

app.on('activate', () => {
  // Specific to macOS
	if (win === null) {
		app.createWindow();
	}
});
