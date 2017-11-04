/* eslint no-eval: 0 */
const ipc = require('electron').ipcRenderer;
const path = require('path');
const {app} = require('electron').remote;

// Const test = remote.getGlobal('test');

const rv = require(path.join(app.getAppPath(), 'src/assets/js/view'));

let id = 0;
let list = 0;
const filesToProcess = {};

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

/*
 * Detect new elements added to the main view and add them
 * to the list if we recognized
 */
(function () {
	const holder = document.getElementById('content');

	holder.ondragover = () => {
		console.log('dragover');
		setImgOpacity(true);
		return false;
	};

	holder.ondragleave = () => {
		console.log('dragleave');
		setImgOpacity(false);
		return false;
	};

	holder.ondragend = () => {
		console.log('dragend');
		setImgOpacity(false);
		return false;
	};

	holder.ondrop = e => {
		e.preventDefault();
		if (list === 0) {
			rv.loadList();
		}
		console.log(e.dataTransfer.files[0]);
		for (const f of e.dataTransfer.files) {
			console.log(f);

			const file = {
				path: f.path,
				type: f.type,
				name: f.name
			};
      // Console.log(JSON.stringify(file))

      // Sending to main.js
			ipc.send('url-reception', file);
		}

		setImgOpacity(false);

		return false;
	};
})();

ipc.on('test-run', () => {
	rv.loadList();
	console.log('test run');
	const file = {
		path: 'test/testbook.epub',
		type: 'file/txt',
		name: 'testbook.epub'
	};

	$(document).ready(() => {
		ipc.send('url-reception', file);
	});
});

ipc.on('element-ok', (event, args) => {
	console.log('element ok');
	// Display item in
	rv.addItem(args);

	// Adding file info in object
	Object.assign(args, {id});
	Object.assign(filesToProcess, {[id]: args});

	console.log(filesToProcess);
	event.sender.send('start-script', args);
	id += 1;
	list += 1;

  // Const message = `Asynchronous message reply: ${arg}`;
  // console.log(args);
  // document.getElementById('async-reply').innerHTML = message;
});

ipc.on('process-finished', (event, args) => {
	$('tr[data-content="' + args.file + '"]')
  .find('i.icon.loading')
  .addClass('inverted green checkmark validate')
  .removeClass('notched circle loading');
});

ipc.on('process-err', (event, args) => {
	$('tr[data-content="' + args.file + '"]')
  .find('i.icon.loading')
  .addClass('inverted red warning sign')
  .removeClass('notched circle loading');
});

/*
 * If autolaunch = false
 * This add to Menu to choose script to launch
 */
ipc.on('add-scripts', (event, args) => {
	// Pause the icon
	$('tr[data-content="' + args.file + '"]')
  .find('i.icon.loading')
  .addClass('inverted blue pause')
  .removeClass('notched circle loading');

	// Add scripts to list
	args.scripts.forEach(s => {
		console.log(s);
		$('tr[data-content="' + args.file + '"]')
    .find('.scriptchooser')
		.append(`<div id="${s.scriptId}" class="item">${s.name}</div>`);
	});
});

ipc.on('eval-browser', (event, args) => {
	eval(args);
});

ipc.on('open-shell', (event, args) => {
	const term = $('.termView[data-term="' + args.file + '"]');
	$('.termView').hide();
	$(term).show();
});

ipc.on('add-process-out', (event, args) => {
	console.log(`${args.data}`);
	console.log($('tr[data-term="' + args.file + '"]').find('pre').html());
	$('tr[data-term="' + args.file + '"]')
  .find('pre').append(`${args.data}`);

	const termView = $('tr[data-term="' + args.file + '"]').find('pre');
	$(termView).scrollTop($(termView)[0].scrollHeight);
});

// Document on click
$(document).on('click', '.showItemInFolder', function () {
	const {shell} = require('electron');
	shell.showItemInFolder($(this).closest('tr').attr('data-content'));
});

$(document).on('click', '.showTerminal', function () {
	const file = $(this).closest('tr').attr('data-content');
	const term = $('.termView[data-term="' + file + '"]');
	$('.termView').not(term).hide();
	$(term).toggle();
	const termPre = $(term).find('pre');
	$(termPre).scrollTop($(termPre)[0].scrollHeight);
});

$(document).on('click', '#processButton', () => {
	ipc.send('start-process-all-files');
});
