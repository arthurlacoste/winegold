const ipc = require('electron').ipcRenderer
function setImgOpacity(value){
  if (value===true){
    document.getElementById("picDrop").setAttribute("class","svgDragover");
    document.getElementById("droptarget").className = "droptargetDragover";
} else {
    document.getElementById("picDrop").setAttribute("class","svgNotDragged");
    document.getElementById("droptarget").className = "droptargetNotDragged";
  }
}

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
        // console.log(e.dataTransfer.files[0]);

        for (let f of e.dataTransfer.files) {

            console.log(f.path);

            ipc.send('asynchronous-message', f.path)


            ipc.on('asynchronous-reply', function (event, arg) {
              const message = `Asynchronous message reply: ${arg}`;
              // document.getElementById('async-reply').innerHTML = message;
            })
        }
        loadList();
        setImgOpacity(false);
        document.body.style.cursor =  "";
        return false;
    };
})();
