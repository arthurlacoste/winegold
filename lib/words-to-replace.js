const fs = require('fs-extra');
const tampax = require('tampax');

let text = '';
let inside = '';
let s = {};
let result = '';

const getContent = function (callback) {
	if (text.indexOf('{{inside}}') === -1) {
		callback();
	} else {
		fs.readFile(s.file, (err, data) => {
			if (err) {
				callback(err);
			}
			inside = data.toString();
			callback();
		});
	}
};

function cb() {
	const args = {
		file: s.fileFormated,
		inside
	};
	console.log(args);
	result = tampax(text, args);
	console.log(result);
}

module.exports = function (cmd, script) {
	text = cmd;
	s = script;
	getContent(cb);
	return result;
};
