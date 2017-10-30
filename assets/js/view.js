const bytes = require('bytes');

function loadList() {
  // Document.getElementById("content").innerHTML='<object type="text/html" data="assets/list.html" ></object>';
	$.ajax({
		url: 'assets/list.html',
		async: false,
		success(data) {
			$('#content').children().remove();
			$('#content').append(data);
			$('.ui.dropdown').dropdown();
		},
		dataType: 'html'
	});
}

// Add menu with all possible extensions
function addMenuExt() {
	return (`<div class="ui floating dropdown search icon button black basic compact">
  <span class="text">Format</span>
  <div class="scriptchooser menu">
  </div>
  </div>`);
}

/*
* Add a line by item needed to converted
* element: object with size, name, and other information
*/
function addItem(element) {
  // Console.log($('#list').length);
	const size = bytes(element.size, {unitSeparator: ' '});
	const html = `
  <tr data-content="${element.path}">
  <td>
    <i id="stateicon" class="circular notched circle loading icon"></i>
  </td>
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
  // Console.log("element added")
  // console.log($('tr[data-content="' + element.path + '"]').length);
}

module.exports.addItem = addItem;
module.exports.addMenuExt = addMenuExt;
module.exports.loadList = loadList;
