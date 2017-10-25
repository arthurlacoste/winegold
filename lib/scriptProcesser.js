
const fs = require('fs')
const yaml = require('js-yaml')
const Data = require('electron-store')
const $ = require('jquery')

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
module.exports.pushIfNotExist = function(element,compare) {
    if (element.indexOf(compare)===-1) {
        element.push(compare);
    }
    return element;
};

// executer a shell command
execute = function(cmd,script, ending=false) {
  const { spawn } = require('child_process');

  let exec = spawn(cmd, [], {shell: true });

  exec.stdout.on('data', (data) => {
    //console.log(`${data}`);
    if(script.execInWindow===true) {
      Object.assign(script, {data: data})
      console.log(`${script.data}`)
      ipcEvent.sender.send('add-process-out',script)
      //cmd = `"${cmd.replace(/'/g, `'\\''`)}"`;
      //cmd = `osascript -e 'tell app "Terminal"' -e 'do script ${cmd}' -e 'end tell'`
    }

  });

  exec.stderr.on('data', (data) => {
    //console.log(`${data}`);
    if(script.execInWindow===true) {
      ipcEvent.sender.send('add-process-out',script)
      //cmd = `"${cmd.replace(/'/g, `'\\''`)}"`;
      //cmd = `osascript -e 'tell app "Terminal"' -e 'do script ${cmd}' -e 'end tell'`
    }
  });

  exec.on('close', (code) => {
    console.log("command END")
      // if cmd is in after, this launch it on background
      if(ending===true) {
        console.log("END")
        ipcEvent.sender.send('process-finished',script)

      }
      // ipcEvent.sender.send('process-finished',script)
  });
}

// parse all yml scripts, return object
module.exports.getAllscripts = function() {
  allScripts = []
  list.forEach(function(f) {
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
module.exports.addScript = function(file) {

  // test YAML integrity
  try {
    var doc = yaml.safeLoad(fs.readFileSync(f, 'utf8'))

    // test presence of

    console.log(typeof(doc.trigger))
    console.log(typeof(doc.cmd))

    // if correct
    data.set('list', pushIfNotExist(list, file));
    console.log(pushIfNotExist(list, file));
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

  try {
    if(typeof(script.cmd.exec)!=='undefined') {
      file = `'${file.replace(/'/g, `'\\''`)}'`;
      script.cmd.exec = script.cmd.exec.replace("<input>",  file)
      script.cmd.exec = script.cmd.exec.replace("<output>", file)
      //console.log("verifier " + script.cmd.exec)
      execute(script.cmd.exec,script,true);
    }

    if(typeof(script.cmd.eval)!=='undefined') {
      eval(script.cmd.eval);
    }

    if(typeof(script.after.exec)!=='undefined') {
      file = `'${file.replace(/'/g, `'\\''`)}'`;
      script.after.exec.replace("<input>", file)
      script.after.exec.replace("<output>", file)
      execute(script.after.exec,script);
    }

    if(typeof(script.after.eval)!=='undefined') {
      //eval(script.after.eval)
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
  console.log(scriptsforThisFile)
}

// Construct
module.exports.init = function(ipcMain) {
  var configFiles = ["_firstTrigger.wg.yml", "_pdf.wg.yml"];
  if (data.get('list')===undefined) {
    data.set('list', configFiles)
  }
  data.set('list', configFiles)

  list = data.get('list')

  // import ipcMain object
  ipcEvent = ipcMain
}
