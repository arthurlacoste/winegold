const {app, BrowserWindow} = require('electron');
if (require('electron-squirrel-startup')) {
	app.quit();
	process.exit(0);
}
const ipc = require('electron').ipcMain;
const path = require('path');
const url = require('url');
const fs = require('fs');
const Config = require('electron-store');
const isDev = require('electron-is-dev');
const id = require('id.log');
const parsePath = require('parse-filepath');
const sp = require('./lib/script-processer');

const config = new Config();
const __base = path.join(__dirname, '/');
const argv = sliceArgv(process.argv);
let winBounds = '';

// Testing argument -t
global.test = /-t/.test(argv[2]);
console.log(global.test);

// If isDev
id.isDev(isDev);
if (isDev) {
	require('electron-reload')(__dirname);
}
id.log(config.get('list'));

let win;

// Reception of an url
ipc.on('url-reception', (event, args) => {
	urlReception(event, args);
});

ipc.on('cancel', (event, args) => {
	if (args === 'all') {
		console.log('Cancel !!!');
		sp.execute.pause();
		sp.execute.kill();
	}
});

function urlReception(event, args) {
	// A console.log(args.path);

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
			win.webContents.send('element-ok', list);
		} else {
      // Element pas ok
		}
	});
}

ipc.on('start-script', (event, args) => {
  // Test if element is allowed
	sp.init(event);
	sp.parseAllScripts(args);
});

ipc.on('start-one-script', (event, args) => {
  // Start script from user selection (renderer onClick)
	sp.launchScript(args.path, args);
});

// This method will be called when Electron has finished
// initialization and is ready to create browser windows.
// Some APIs can only be used after this event occurs.

app.on('ready', () => {
	const optsInit = {
		minHeight: 340,
		minWidth: 300,
		icon: 'icons/icon.icns',
		show: false
	};
	const opts = {};
	Object.assign(opts, config.get('winBounds'), optsInit);
	console.log(opts);

	app.on('open-file', onOpen);
	app.on('open-url', onOpen);

	win = new BrowserWindow(opts);

	console.log(__dirname);

	win.loadURL(url.format({
		pathname: path.join(__dirname, 'index.html'), //
    // pathname: path.join(__dirname, 'assets/list.html'),
		protocol: 'file:',
		slashes: true
	}));

	win.once('ready-to-show', () => {
		win.show();
		if (global.test) {
			win.webContents.send('test-run');
		}
	});

	win.setMinimumSize(320, 300);

	if (isDev || global.test) {
		win.webContents.openDevTools();
	}
  // Save window size and position
	win.on('close', () => {
		console.log(win.getBounds());
		config.set('winBounds', winBounds);
	});

	win.on('move', () => {
		winBounds = win.getBounds();
	});

  // Emitted when the window is closed.
	win.on('closed', () => {
		win = null;
	});

	require(path.join(__base, 'lib/mainmenu'));
});

// Quit when all windows are closed. I'm note sure to keep this
app.on('window-all-closed', () => {
	app.quit();
});

app.on('activate', () => {
  // Specific to macOS
	if (win === null) {
		app.createWindow();
	}
});

function onOpen(e, path) {
	e.preventDefault();
	const p = parsePath(path);
	win.webContents.send('log', path);
	const file = {
		path,
		type: p.ext,
		name: p.basename
	};
	urlReception(win.webContents, file);

	if (app.ipcReady) {
		setTimeout(() => win.main.show(), 100);
		win.webContents.send('log', 'app ready <3');
	} else {
			// Argv.push(id);
	}
}

// Remove leading args.
// Production: 1 arg, eg: /Applications/winegold.app/Contents/MacOS/winegold
// Development: 2 args, eg: electron .
// Test: 4 args, eg: electron -r .../mocks.js .
function sliceArgv(argv) {
	return argv.slice(config.IS_PRODUCTION ? 1 :
    config.IS_TEST ? 4 :
    2);
}
