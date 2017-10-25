var bytes = require('bytes');

function loadList() {
  //document.getElementById("content").innerHTML='<object type="text/html" data="assets/list.html" ></object>';
  $.ajax({
    url: "assets/list.html",
    async: false,
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
  //console.log($('#list').length);
  let size = bytes(element.size, {unitSeparator: ' '})
  html = `
  <tr data-content="${element.path}">
  <td><i class="icon loading asterisk"></i></td>
  <td><div class="name"><span class="innerName" data-filetype="${element.name.split('.').pop()}">${element.name}</sapn></div><span class="icon icon-search"></span></td>
  <td class="iconButtonCell">
    <div class="showItemInFolder ui negative basic button compact icon"><i class="search icon"></i></div>
    <div class="showTerminal ui negative basic button compact icon"><i class="terminal icon"></i></div>
  </td>
  <td>${addMenuExt()}</td>
  <td>${size}</td>
  </tr>
  <tr class="termView" data-term="${element.path}">
      <th colspan="5">
      <pre></pre>
      </th>
  </tr>`;
  $('#list').append(html);
  $('.ui.dropdown').dropdown();
  //console.log("element added")
  //console.log($('tr[data-content="' + element.path + '"]').length);

}

// <td>*0.0009765625}Ko</td>
