const ipc = require('electron').ipcRenderer;
const dragDrop = require('drag-drop');
const id = require('id.log');
const rv = require('./assets/js/view');

let idFile = 0;
let list = 0;
const filesToProcess = {};

$(document).ready(() => {
	ipc.send('init-script-processer');
});

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
	Object.assign(args, {idFile, status: 'waiting'});
	Object.assign(filesToProcess, {[idFile]: args});
	updateProcessButton();
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

// Fetch if others files need to be process
function updateProcessButton() {
	let toProcess = false;
	Object.keys(filesToProcess).map(key => {
		console.log(key + ' ' + filesToProcess[key].path);
		console.log(key + ' ' + filesToProcess[key].status);
		if (filesToProcess[key].status !== 'err' &&
        filesToProcess[key].status !== 'finished' &&
        filesToProcess[key].status !== 'waiting') {
			toProcess = true;
			return true;
		}
		return true;
	});
	console.log(toProcess);
	if (toProcess === true) {
		$('#processButton').show();
	} else {
		$('#processButton').hide();
	}
}

ipc.on('process-finished', (event, args) => {
	if (filesToProcess.status !== 'err') {
		filesToProcess[args.idFile].status = 'finished';
	}

	updateProcessButton();

  // Edit icon
	$('tr[data-content="' + args.idFile + '"]')
  .find('i.icon.loading')
  .addClass('inverted green checkmark validate')
  .removeClass('notched circle loading');
});

ipc.on('process-err', (event, args) => {
	filesToProcess[args.idFile].status = 'err';
	updateProcessButton();
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
	filesToProcess[args.idFile].scripts = {};

	// Add scripts to list
	args.scripts.forEach(s => {
		filesToProcess[args.idFile].scripts[s.scriptId] = s;
		console.log(s);
		$('tr[data-content="' + args.idFile + '"]')
    .find('.scriptchooser')
		.append(`<div id="scriptchooserinner" data-fileid="${args.idFile}" data-scriptid="${s.scriptId}" class="item">${s.name}</div>`);
	});
});

// Pause the icon
ipc.on('icon-pause', (event, args) => {
	filesToProcess[args.idFile].status = 'pause';
	updateProcessButton();
	$('tr[data-content="' + args.idFile + '"]')
.find('i.icon.loading')
.addClass('inverted blue pause')
.removeClass('notched circle loading');
});

ipc.on('eval-browser', (event, args) => {
	eval(args);
});

ipc.on('log', (event, args) => {
	id.log(args);
});

// Force to open shellview
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

	try {
		$(termView).scrollTop($(termView)[0].scrollHeight);
	} catch (err) {
		console.log('No scrollTop. Window is closed?');
	}
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

$(document).on('click', '#cancel', () => {
	ipc.send('cancel', 'all');

	// Add warning icon on loading scripts
	$('i.icon.loading').each(function () {
		$(this)
		.addClass('inverted red warning sign')
		.removeClass('notched circle loading');
	});
});

$(document).on('click', '#scriptchooserinner', function () {
	const scriptid = $(this).attr('data-scriptid');
	const fileid = $(this).attr('data-fileid');
	const script = filesToProcess[fileid].scripts[scriptid];
	console.log(`Start script ${script.name}`);
	Object.assign(script, filesToProcess[fileid]);

	// Edit icon
	$('i[data-icon="' + fileid + '"]')
	.removeClass('inverted blue pause')
  .removeClass('inverted green checkmark validate')
	.addClass('notched circle loading');

	ipc.send('start-one-script', script);
});
