var bytes = require('bytes');

function loadList() {
  //document.getElementById("content").innerHTML='<object type="text/html" data="assets/list.html" ></object>';
  $.ajax({
    url: "assets/list.html",
    success: function (data) {
      $('#content').children().remove();
      $('#content').append(data);
      $('.ui.dropdown').dropdown();
    },
    dataType: 'html'
  });
}


// add menu with all possible extensions
function addMenuExt() {
  return(`<div class="ui floating dropdown search icon button black basic compact">
  <span class="text">Format</span>
  <div class="menu">
  <div class="item">png</div>
  <div class="item">jpg</div>
  <div class="item">svg</div>
  </div>
  </div>`)
}



/*
* add a line by item needed to converted
* element: object with size, name, and other information
*/
function addItem(element) {
  console.log("test");
  let size = bytes(element.size, {unitSeparator: ' '})
  html = `
  <tr>
  <td class="iconCell"><i class="icon loading asterisk"></i></td>
  <td><div class="name"><span class="innerName" data-content="${element.name}" data-filetype="${element.name.split('.').pop()}">${element.name}</sapn></div><span class="icon icon-search"></span></td>
  <td class="minCell">${addMenuExt()}</td>
  <td class="minCell">${size}</td>
  </tr>`;
  $('#list').append(html);
  $('.ui.dropdown').dropdown();
}

// <td>*0.0009765625}Ko</td>
