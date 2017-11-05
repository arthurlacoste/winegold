const bytes = require('bytes');

function loadList() {
	// From index.html
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
	console.log(`Add on renderer ${element.idFile} : "${element.name}"`);
	const size = bytes(element.size, {unitSeparator: ' '});
	const html = `
  <tr data-content="${element.idFile}">
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
  <tr class="termView" data-term="${element.idFile}">
      <th colspan="5">
      <pre></pre>
      </th>
  </tr>`;
	$('#list').append(html);
	$('.ui.dropdown').dropdown();
  // Console.log("element added")
  // console.log($('tr[data-content="' + element.path + '"]').length);
}

/*
 * SetImgOpacity(bool) change class of each element affected by dragover
 * statment
 * bool: Boolean with tue if element is dragged over
 */
function setImgOpacity(value) {
	try {
		if (value === true) {
			document.getElementById('picDrop').setAttribute('class', 'svgDragover');
			document.getElementById('droptarget').className = 'droptargetDragover';
		} else {
			document.getElementById('picDrop').setAttribute('class', 'svgNotDragged');
			document.getElementById('droptarget').className = 'droptargetNotDragged';
		}
	} catch (err) {
		console.log('Always in list vue, no render here');
	}
}

module.exports.addItem = addItem;
module.exports.addMenuExt = addMenuExt;
module.exports.loadList = loadList;
module.exports.setImgOpacity = setImgOpacity;
