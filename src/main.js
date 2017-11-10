const {app, BrowserWindow} = require('electron');
// Exit the app if we are in the Windows setup case
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

ipc.on('init-script-processer', event => {
	sp(event); // Init script-processer
});
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
	const bounds = win.getBounds();
	if (bounds.height < 400 && bounds.width < 360)	{
		win.setSize(400, 350, true);
	}
});

ipc.on('cancel', (event, args) => {
	if (args === 'all') {
		console.log('Cancel !!!');
		sp.execute.pause();
		sp.execute.kill();
	}
});

function urlReception(event, args) {
	console.log(args.name);
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
		} else {
			const list = {};

      // Merging data from all sources
			Object.assign(list, stats, args);
      // Sending element to main list
			win.webContents.send('element-ok', list);
		}
	});
}

ipc.on('start-script', (event, args) => {
  // Test if element is allowed
	console.log('file 1');
	sp.processScript(event, args);
});

ipc.on('start-one-script', (event, args) => {
  // Start script from user selection (renderer onClick)
	sp.launchScript({file: args.path, idFile: args.idFile}, args);
});

const getBounds = config.get('winBounds');

app.on('ready', () => {
	const optsInit = {
		minHeight: 300,
		minWidth: 330,
		icon: path.join('icons/icon.png'),
		show: false
	};
	const opts = {};

	Object.assign(opts, getBounds, optsInit);
	console.log(opts);

	app.on('open-file', onOpen);
	app.on('open-url', onOpen);

	win = new BrowserWindow(opts);

	console.log(__dirname);

	win.loadURL(url.format({
		pathname: path.join(__dirname, 'index.html'),
		protocol: 'file:',
		slashes: true
	}));

	win.once('ready-to-show', () => {
		win.show();
		if (global.test) {
			win.webContents.send('test-run');
		}
	});

	if (!getBounds || !getBounds.width) {
		win.setSize(350, 300);
	}

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
		win.webContents.send('log', 'App ready <3');
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
