const {app, BrowserWindow} = require("electron");
global.__base = __dirname + '/';
require('electron-reload')(__dirname);

const path = require('path')
const url = require('url')
const fs = require('fs')
const Config = require('electron-store')
const config = new Config()
// const scriptsList = new Config({default: })
const ipc = require('electron').ipcMain
var idLog = require('id.log');
var id = new idLog();
var extend = require('extend');

id.log(config.get('scriptsList'));
// Reception of an url
ipc.on('url-reception', function urlReception(event, args) {
  console.log(args.path)


  //console.log(scripts);

  recognizedExtention = true

  // Get informations about the file
  fs.stat(args.path, function(err, stats) {
    if(err) {
      console.log(err);
      return;
    }
    if(stats.isDirectory()){
      fs.readdir(args.path, (err, files) => {
        files.forEach(file => {

          let fileInfo = {
            "path": args.path + "/" + file,
            "name": file
          }

          // search files recursively
          urlReception(event, fileInfo)
        });
      })
    } else if(recognizedExtention===true) {
      let list = {};

      // merging data from all sources
      Object.assign(list, stats, args);

      // sending element to main list
      event.sender.send('element-ok', list)

    } else {
      // element pas ok

      // deja dans la liste, etc
    }

  })
})

ipc.on("start-script", function(event, args) {
  // test if element is allowed
  let sp = require(__base+'lib/scriptProcesser.js')
  sp.init(event);
  sp.parseAllScripts(args.path);
})

// Keep a global reference of the window object, if you don't, the window will
// be closed automatically when the JavaScript object is garbage collected.

let win

// This method will be called when Electron has finished
// initialization and is ready to create browser windows.
// Some APIs can only be used after this event occurs.

app.on('ready', () => {
  let optsInit = {
    minHeight: 340,
    minWidth: 300,
    show: false
  }
  let opts = {}
  Object.assign(opts, config.get('winBounds'), optsInit)
  console.log(opts)
  win = new BrowserWindow(config.get('winBounds'))
  win.loadURL(url.format({
    pathname: path.join(__dirname, 'index.html'), //
    //pathname: path.join(__dirname, 'assets/list.html'),
    protocol: 'file:',
    slashes: true
  }))

  win.once('ready-to-show', win.show)
  win.setMinimumSize(320,300);

  win.webContents.openDevTools()
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
    win = null
  })
})

// Quit when all windows are closed.
app.on('window-all-closed', function () {
  // specific to macOS
  if (process.platform !== 'darwin') {
    app.quit()
  }
})

app.on('activate', function () {
  // specific to macOS
  if (win === null) {
    createWindow()
  }

})
