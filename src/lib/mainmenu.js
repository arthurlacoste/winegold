const {Menu, dialog, app} = require('electron');
const Data = require('electron-store');

const data = new Data();

const template = [
	{
		label: 'Scripts',
		submenu: [
			{
				label: 'See all scripts',
				role: 'allScripts',
				accelerator: process.platform === 'darwin' ? 'Command+S' : 'Ctrl+S',
				click() {
					require('electron').shell.showItemInFolder(data.get('scriptPath'));
				}
			},

			{
				label: 'Edit script directory',
				role: 'editScript',
				accelerator: 'CmdOrCtrl+Alt+A',

				click() {
					dialog.showOpenDialog({
						properties: ['openDirectory']
					}, path => {
						if (path) {
							data.set('scriptPath', path[0]);
						}
					});
				}
			},
			{
				label: 'See script documentation',
				role: 'seeScriptDocs',
				accelerator: 'CmdOrCtrl+D',
				click(item, focusedWindow) {
					if (focusedWindow) {
						require('electron').shell.openExternal('https://github.com/arthurlacoste/winegold/blob/master/docs/scripts.md#script-documentation');
					}
				}
			}
		]
	},
	{
		label: 'Edit',
		submenu: [
			{
				role: 'undo'
			},
			{
				role: 'redo'
			},
			{
				type: 'separator'
			},
			{
				role: 'cut'
			},
			{
				role: 'copy'
			},
			{
				role: 'paste'
			},
			{
				role: 'pasteandmatchstyle'
			},
			{
				role: 'delete'
			},
			{
				role: 'selectall'
			}
		]
	},
	{
		label: 'View',
		submenu: [
			{
				label: 'Reload',
				accelerator: 'CmdOrCtrl+R',
				click(item, focusedWindow) {
					if (focusedWindow) {
						focusedWindow.reload();
					}
				}
			},
			{
				type: 'separator'
			},
			{
				role: 'resetzoom'
			},
			{
				role: 'zoomin'
			},
			{
				role: 'zoomout'
			},
			{
				type: 'separator'
			},
			{
				role: 'togglefullscreen'
			}
		]
	},
	{
		role: 'window',
		submenu: [
			{
				role: 'minimize'
			},
			{
				role: 'close'
			}
		]
	},
	{
		role: 'help',
		submenu: [
			{
				label: 'Toggle Developer Tools',
				accelerator: process.platform === 'darwin' ? 'Alt+Command+I' : 'Ctrl+Shift+I',
				click(item, focusedWindow) {
					if (focusedWindow) {
						focusedWindow.webContents.toggleDevTools();
					}
				}
			},
			{
				type: 'separator'
			},
			{
				label: 'Report an issue',
				click() {
					require('electron').shell.openExternal('https://github.com/arthurlacoste/winegold/issues');
				}
			},
			{
				label: 'Contribute on GitHub',
				accelerator: 'CmdOrCtrl+G',
				click() {
					require('electron').shell.openExternal('https://github.com/arthurlacoste/winegold');
				}
			}
		]
	}
];

if (process.platform === 'darwin') {
	const name = app.getName();
	template.unshift({
		label: name,
		submenu: [
			{
				role: 'about'
			},
			{
				type: 'separator'
			},
			{
				role: 'services',
				submenu: []
			},
			{
				type: 'separator'
			},
			{
				role: 'hide'
			},
			{
				role: 'hideothers'
			},
			{
				role: 'unhide'
			},
			{
				type: 'separator'
			},
			{
				role: 'quit'
			}
		]
	});

  // Edit menu.
	template[1].submenu.push(
		{
			type: 'separator'
		},
		{
			label: 'Speech',
			submenu: [
				{
					role: 'startspeaking'
				},
				{
					role: 'stopspeaking'
				}
			]
		}
  );
  // Window menu.
	template[3].submenu = [
		{
			label: 'Close',
			accelerator: 'CmdOrCtrl+W',
			role: 'close'
		},
		{
			label: 'Minimize',
			accelerator: 'CmdOrCtrl+M',
			role: 'minimize'
		},
		{
			label: 'Zoom',
			role: 'zoom'
		},
		{
			type: 'separator'
		},
		{
			label: 'Bring All to Front',
			role: 'front'
		}
	];
}

const menu = Menu.buildFromTemplate(template);
Menu.setApplicationMenu(menu);
