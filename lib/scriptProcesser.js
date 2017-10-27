const {app} = require('electron');
const fs = require('fs-extra')
const yaml = require('js-yaml')
const Data = require('electron-store')
const $ = require('jquery')
const path = require('path')


let ipcEvent
let data = new Data();
let allScripts = {}
let list

/*
 * pushIfNotExist() push an element if is not
 * already exist in the array
 * element: Array object
 * compare: string to add
 * return:  array
 */
pushIfNotExist = function(element,compare) {
    if (element.indexOf(compare)===-1) {
        element.push(compare);
    }
    return element;
};

evalDeep = function(js,script) {
  var { forkString } = require('child-process-fork-string');

  // with silent: true, you can see and use stdout/stderr
  const exec = forkString(js, { silent: true })

  exec.stdout.on('data', (data) => {
    console.log(data);
    Object.assign(script, {data: data})
    ipcEvent.sender.send('add-process-out',script)
  });

  exec.stderr.on('data', (data) => {
    console.log(data);
    Object.assign(script, {data: `${data}`})
    ipcEvent.sender.send('add-process-out',script)
    ipcEvent.sender.send('process-err',script)
  });

  exec.on('close', (code) => {
    if (code === 0) {
      ipcEvent.sender.send('process-finished',script)
    } else {
      ipcEvent.sender.send('process-err',script)
    }
  });
}

// executer a shell command
execute = function(cmd,script, ending=false) {
  const { spawn } = require('child_process');

  let exec = spawn(cmd, [], {shell: true });

  exec.stdout.on('data', (data) => {
    if(script.execInWindow===true) {
      Object.assign(script, {data: data})
      console.log(`${script.data}`)
      ipcEvent.sender.send('add-process-out',script)
      //cmd = `"${cmd.replace(/'/g, `'\\''`)}"`;
      //cmd = `osascript -e 'tell app "Terminal"' -e 'do script ${cmd}' -e 'end tell'`
    }

  });

  exec.stderr.on('data', (data) => {
    if(script.execInWindow===true) {
      Object.assign(script, {data: data})
      ipcEvent.sender.send('add-process-out',script)
      ipcEvent.sender.send('process-err',script)
    }
  });

  exec.on('close', (code) => {
    console.log("command END")

      // if cmd is in after, this launch it on background
      if(ending===true) {
        console.log("END")
        ipcEvent.sender.send('process-finished',script)

      }
  });
}

// parse all yml scripts, return object
module.exports.getAllscripts = function() {
  allScripts = []
  list.forEach(function(f) {
    let path = require('path')
    const {app} = require('electron');
    //console.log(path.resolve(f))
    if(! path.isAbsolute(f)) {
      f = path.join(app.getAppPath() + "/" + f)
      console.log(f)
    }
    try {
      var doc = yaml.safeLoad(fs.readFileSync(f, 'utf8'))
      allScripts.push(doc)
      //console.log(doc)

    } catch (e) {
      console.log(e)
    }
  })

  //console.log(allScripts);
  return allScripts
}


/*
 * verify and add a script file if he respect format
 * file: complete file with path
 * return: true if script was added
 */
addScript = function(file) {
  // test YAML integrity
  // script.cmd.exec = script.cmd.exec.replace("<filename>",  file)
  //console.log(script.cmd.exec)
  try {
    var doc = yaml.safeLoad(fs.readFileSync(file, 'utf8'))

    // test presence of triggers and command
    console.log(typeof(doc.trigger))

    console.log(typeof(doc.cmd))

    // if correct
    data.set('list', pushIfNotExist(list, file));
    return true
  } catch (e) {
    console.log(e)
  }
}



launchScript = function(file, script){
  Object.assign(script,{"file":file})
  //console.log(script)
  if(typeof(script.trigger.fileExtension)==="string") {
    if(file.indexOf(script.trigger.fileExtension)===-1){
      return false;
    }
  }
  file = `'${file.replace(/'/g, `'\\''`)}'`;
  try {
    if(typeof(script.cmd.exec)!=='undefined') {

      script.cmd.exec = script.cmd.exec.replace("<input>",  file)
      script.cmd.exec = script.cmd.exec.replace("<output>", file)
      //console.log("verifier " + script.cmd.exec)
      execute(script.cmd.exec,script,true);
    }

    if(typeof(script.cmd.eval)!=='undefined') {
      script.cmd.eval = script.cmd.eval.replace("<filename>",  file)
      evalDeep(script.cmd.eval, script);
    }

    if(typeof(script.cmd.internal)!=='undefined' && script.cmd.internal === "addScript") {
      addScript(script.file);
    }

    if(typeof(script.after.exec)!=='undefined') {
      script.after.exec = script.after.exec.replace("<input>", file)
      script.after.exec = script.after.exec.replace("<output>", file)
      execute(script.after.exec,script);
    }

    if(typeof(script.after.eval)!=='undefined') {
      ipcEvent.sender.send('eval-browser',script.after.eval)
    }
  } catch (e) {
    console.log(e)
  }

}

/*
 * parseAllScripts for one file
 *
 */
module.exports.parseAllScripts = function(file) {
  let scriptsforThisFile = []
  this.getAllscripts();
  allScripts.forEach(function(s) {
    //console.log(typeof(s.trigger.fileExtension))
    if(typeof(s.trigger.fileExtension)==="string" && file.indexOf(s.trigger.fileExtension)!=-1) {
      scriptsforThisFile.push(s)
      if (s.autolaunch===true) {launchScript(file, s)}
    } else if(typeof(s.trigger.fileExtension)==="object") {
      s.trigger.fileExtension.some(function(ext) {
        if (file.indexOf(ext)!=-1) {
          console.log(ext + " found")
          scriptsforThisFile.push(s)
          if (s.autolaunch===true) {launchScript(file, s)}
          return false
        }
      })
    }
  })
  if(scriptsforThisFile.length===0){
    console.log("rien")
    ipcEvent.sender.send('process-err', {file: file})
  }
  console.log(scriptsforThisFile)
}

// Construct
module.exports.init = function(ipcMain) {
  var configFiles = ["scripts/config.add.yml", "scripts/pdf.add.yml"];
  if (data.get('list')===undefined) {
    data.set('list', configFiles)
  }
  data.set('list', configFiles)

  list = data.get('list')

  // import ipcMain object
  ipcEvent = ipcMain

  list.forEach(function(f) {
    console.log("trying : " + app.getPath('userData') + "/" + f);
    fs.exists(app.getPath('userData') + "/" + f, function(exists) {
      if (!exists) {
        fs.copy(app.getAppPath() + "/" + f,
         app.getPath('userData') + "/" + f, function (err) {
          if (err) {
            console.error(err);
          } else {
            console.log("success: " + app.getPath('userData') + "/" + f);
          }
        });
      }
    });

  })
}
