/* eslint no-eval: 0 */
const ipc = require('electron').ipcRenderer;
resolve = require('path').resolve
var rv = require('assets/js/view');

let list = 0;
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

	holder.ondrop = e => {
		e.preventDefault();
		if (list === 0) {
			rv.loadList();
		}
    // Console.log(e.dataTransfer.files[0]);
		for (const f of e.dataTransfer.files) {
			console.log(f);

			const file = {
				path: f.path,
				type: f.type,
				name: f.name
			};
      // Console.log(JSON.stringify(file))

      // sending to main.js
			ipc.send('url-reception', file);
		}

		setImgOpacity(false);

		return false;
	};
})();

ipc.on('element-ok', (event, args) => {
	rv.addItem(args);
	event.sender.send('start-script', args);
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

ipc.on('eval-browser', (event, args) => {
	eval(args);
});

ipc.on('add-process-out', (event, args) => {
	console.log(`${args.data}`);
	console.log($('tr[data-term="' + args.file + '"]').find('pre').html());
	$('tr[data-term="' + args.file + '"]')
  .find('pre').append(`${args.data}`);

	const termView = $('tr[data-term="' + args.file + '"]').find('pre');
	$(termView).scrollTop($(termView)[0].scrollHeight);
});

//document on click
$(document).on('click', '.showItemInFolder', function () {
	const {shell} = require('electron');
	shell.showItemInFolder($(this).closest('tr').attr('data-content'));
});

$(document).on('click', '.showTerminal', function () {
	const file = $(this).closest('tr').attr('data-content');
	const term = $('.termView[data-term="' + file + '"]');
	$(term).toggle();
	const termPre = $(term).find('pre');
	$(termPre).scrollTop($(termPre)[0].scrollHeight);
});
