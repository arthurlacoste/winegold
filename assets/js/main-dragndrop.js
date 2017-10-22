const ipc = require('electron').ipcRenderer

var list = 0;
/*
 * setImgOpacity(bool) change class of each element affected by dragover
 * statment
 * bool: Boolean with tue if element is dragged over
 */

function setImgOpacity(value){
  try {
    if (value===true){
      document.getElementById("picDrop").setAttribute("class","svgDragover");
      document.getElementById("droptarget").className = "droptargetDragover";
    } else {
      document.getElementById("picDrop").setAttribute("class","svgNotDragged");
      document.getElementById("droptarget").className = "droptargetNotDragged";
    }
  } catch(e) {
    console.log("Always in list vue, no render here");
  }
}

/*
 * Detect new elements added to the main view and add them
 * to the list if we recognized
 */

(function () {
  var holder = document.getElementById('content');

  holder.ondragover = () => {
    setImgOpacity(true);
    return false;
  };

  holder.ondragleave = () => {
    setImgOpacity(false);
    return false;
  };

  holder.ondragend = () => {
    setImgOpacity(false);
    return false;
  };

  holder.ondrop = (e) => {
    e.preventDefault();
    if(list===0) {
      loadList();
    }
    // console.log(e.dataTransfer.files[0]);
    for (let f of e.dataTransfer.files) {
      console.log(f);

      let file = {
        "path": f.path,
        "type": f.type,
        "name": f.name
      }
      //console.log(JSON.stringify(file))

      // sending to main.js
      ipc.send('url-reception', file)
    }


    setImgOpacity(false);

    return false;
  };
})();

ipc.on('element-ok', function (event, arg) {
  addItem(arg);
  list += 1;
  //const message = `Asynchronous message reply: ${arg}`;
  console.log(arg);
  // document.getElementById('async-reply').innerHTML = message;
})
