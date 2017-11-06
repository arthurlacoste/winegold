const path = require('path');
const electron = require('electron');
const appConfig = require('application-config')('winegold');
const arch = require('arch');

const APP_NAME = 'winegold';
const APP_TEAM = 'Arthur Lacoste';
const APP_VERSION = require('../package.json').version;

const IS_TEST = isTest();
const PORTABLE_PATH = IS_TEST ?
  path.join(process.platform === 'win32' ? 'C:\\Windows\\Temp' : '/tmp', 'winegoldTest') :
  path.join(path.dirname(process.execPath), 'Portable Settings');
const IS_PRODUCTION = isProduction();
const IS_PORTABLE = isPortable();

module.exports = {
	APP_COPYRIGHT: 'Copyright © 2017 ' + APP_TEAM,
	APP_FILE_ICON: path.join(__dirname, '..', 'src/icons', 'icon'),
	APP_ICON: path.join(__dirname, '..', 'src/icons', 'icon'),
	APP_NAME,
	APP_TEAM,
	APP_VERSION,
	APP_WINDOW_TITLE: APP_NAME + ' (BETA)',

	CONFIG_PATH: getConfigPath(),

	DELAYED_INIT: 3000 /* 3 seconds */,

	DEFAULT_DOWNLOAD_PATH: getDefaultDownloadPath(),

	GITHUB_URL: 'https://github.com/arthurlacoste/winegold',
	GITHUB_URL_ISSUES: 'https://github.com/arthurlacoste/winegold/issues',
	GITHUB_URL_RAW: 'https://raw.githubusercontent.com/arthurlacoste/winegold/master',

	HOME_PAGE_URL: 'https://github.com/arthurlacoste/winegold',

	IS_PORTABLE,
	IS_PRODUCTION,
	IS_TEST,

	OS_SYSARCH: arch() === 'x64' ? 'x64' : 'ia32',

	POSTER_PATH: path.join(getConfigPath(), 'Posters'),
	ROOT_PATH: path.join(__dirname, '..'),
	STATIC_PATH: path.join(__dirname, '..', 'src/')
};

function getConfigPath() {
	if (IS_PORTABLE) {
		return PORTABLE_PATH;
	}
	return path.dirname(appConfig.filePath);
}

function getDefaultDownloadPath() {
	if (IS_PORTABLE) {
		return path.join(getConfigPath(), 'Downloads');
	}
	return getPath('downloads');
}

function getPath(key) {
	if (!process.versions.electron) {
    // Node.js process
		return '';
	} else if (process.type === 'renderer') {
    // Electron renderer process
		return electron.remote.app.getPath(key);
	}
    // Electron main process
	return electron.app.getPath(key);
}

function isTest() {
	return process.env.NODE_ENV === 'test';
}

function isPortable() {
	if (IS_TEST) {
		return true;
	}

	if (process.platform !== 'win32' || !IS_PRODUCTION) {
    // Fast path: Non-Windows platforms should not check for path on disk
		return false;
	}

	const fs = require('fs');

	try {
    // This line throws if the "Portable Settings" folder does not exist, and does
    // nothing otherwise.
		fs.accessSync(PORTABLE_PATH, fs.constants.R_OK | fs.constants.W_OK);
		return true;
	} catch (err) {
		return false;
	}
}

function isProduction() {
	if (!process.versions.electron) {
    // Node.js process
		return false;
	}
	if (process.platform === 'darwin') {
		return !/\/Electron\.app\//.test(process.execPath);
	}
	if (process.platform === 'win32') {
		return !/\\electron\.exe$/.test(process.execPath);
	}
	if (process.platform === 'linux') {
		return !/\/electron$/.test(process.execPath);
	}
}
