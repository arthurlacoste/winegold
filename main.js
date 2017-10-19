const {app, BrowserWindow} = require("electron");

const path = require('path')
const url = require('url')
const Config = require('electron-store')
const config = new Config()
const ipc = require('electron').ipcMain

ipc.on('asynchronous-message', function (event, arg) {
  event.sender.send('asynchronous-reply', 'pong')
  console.log(arg)
})

// Keep a global reference of the window object, if you don't, the window will
// be closed automatically when the JavaScript object is garbage collected.

let win

// This method will be called when Electron has finished
// initialization and is ready to create browser windows.
// Some APIs can only be used after this event occurs.

app.on('ready', () => {
  let opts = {show: false}
  Object.assign(opts, config.get('winBounds'))
  console.log(opts)
  win = new BrowserWindow(config.get('winBounds'))
  win.loadURL(url.format({
    //pathname: path.join(__dirname, 'node_modules/drop-anywhere/example.html'), //
    pathname: path.join(__dirname, 'assets/list.html'),
    protocol: 'file:',
    slashes: true
  }))
  // Open the DevTools.
  // win.webContents.openDevTools()

  win.once('ready-to-show', win.show)

  // win.webContents.openDevTools()
  // save window size and position
  win.on('close', () => {
    console.log(win.getBounds())
    config.set('winBounds', win.getBounds())
  })

  win.on('move', () => {
    console.log(win.getBounds())
    config.set('winBounds', win.getBounds())
  })

  // Emitted when the window is closed.
  win.on('closed', function () {
    // Dereference the window object, usually you would store windows
    // in an array if your app supports multi windows, this is the time
    // when you should delete the corresponding element.
    win = null
  })
})

// Quit when all windows are closed.
app.on('window-all-closed', function () {
  // On OS X it is common for applications and their menu bar
  // to stay active until the user quits explicitly with Cmd + Q
  if (process.platform !== 'darwin') {
    app.quit()
  }
})

app.on('activate', function () {
  // On OS X it's common to re-create a window in the app when the
  // dock icon is clicked and there are no other windows open.
  if (win === null) {
    createWindow()
  }

})

// In this file you can include the rest of your app's specific main process
// code. You can also put them in separate files and require them here.
