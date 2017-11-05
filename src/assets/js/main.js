/* eslint no-eval: 0, import/no-unresolved: [2, { ignore: ['\.assets$'] }] */

const ipc = require('electron').ipcRenderer;
const dragDrop = require('drag-drop');
const id = require('id.log');

const rv = require('./assets/js/view');

let idFile = 0;
let list = 0;
const filesToProcess = {};

/*
 * Detect new elements added to the main view and add them
 * to the list if we recognized
 */
dragDrop('#content', {
	onDrop(files) {
		files.forEach(f => {
			const file = {
				path: f.path,
				type: f.type,
				name: f.name
			};

      // Sending to main.js
			ipc.send('url-reception', file);
			rv.setImgOpacity(false);
		});
	},
	onDragEnd() {
		rv.setImgOpacity(true);
	},
	onDragOver() {
		rv.setImgOpacity(true);
	},
	onDragLeave() {
		rv.setImgOpacity(false);
	}
});

ipc.on('test-run', () => {
	rv.loadList();
	console.log('test run');
	const file = {
		path: 'build/test/testbook.epub',
		type: 'file/txt',
		name: 'testbook.epub'
	};

	$(document).ready(() => {
		ipc.send('url-reception', file);
	});
});

ipc.on('element-ok', (event, args) => {
	if (list === 0) {
		rv.loadList();
	}

	// Adding file info in object
	Object.assign(args, {idFile});
	Object.assign(filesToProcess, {[idFile]: args});

  // Display item in
	rv.addItem(args);

	console.log(filesToProcess);
	event.sender.send('start-script', args);
	idFile += 1;
	list += 1;

  // Const message = `Asynchronous message reply: ${arg}`;
  // console.log(args);
  // document.getElementById('async-reply').innerHTML = message;
});

ipc.on('process-finished', (event, args) => {
	$('tr[data-content="' + args.idFile + '"]')
  .find('i.icon.loading')
  .addClass('inverted green checkmark validate')
  .removeClass('notched circle loading');
});

ipc.on('process-err', (event, args) => {
	$('tr[data-content="' + args.idFile + '"]')
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
	$('tr[data-content="' + args.idFile + '"]')
  .find('i.icon.loading')
  .addClass('inverted blue pause')
  .removeClass('notched circle loading');

	// Add scripts to list
	args.scripts.forEach(s => {
		console.log(s);
		$('tr[data-content="' + args.idFile + '"]')
    .find('.scriptchooser')
		.append(`<div id="${s.scriptId}" class="item">${s.name}</div>`);
	});
});

ipc.on('eval-browser', (event, args) => {
	eval(args);
});

ipc.on('log', (event, args) => {
	id.log(args);
});

ipc.on('open-shell', (event, args) => {
	const term = $('.termView[data-term="' + args.idFile + '"]');
	$('.termView').hide();
	$(term).show();
});

// Args: script used & data
ipc.on('add-process-out', (event, args) => {
	console.log(args);
	console.log(`${args.data}`);
	console.log($('tr[data-term="' + args.idFile + '"]').find('pre').html());
	$('tr[data-term="' + args.idFile + '"]')
  .find('pre').append(`${args.data}`);

	const termView = $('tr[data-term="' + args.idFile + '"]').find('pre');
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
