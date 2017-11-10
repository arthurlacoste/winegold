const fs = require('fs-extra');
const tampax = require('tampax');
const parsePath = require('parse-filepath');

let result = '';

// Parser,
function tampaxParse(text, s) {
	const p = parsePath(s.file);

	const args = {
		file: s.fileFormated,
		dir: p.dir,
		name: p.name,
		ext: p.ext,
		namebase: p.stem,
		inside: result,
		path: p.path
	};

	return (tampax(text, args));
}

// Asynchronous method, if we need to read entire file
const getContent = function (text, s, callback) {
	console.log('S', s);
	console.log('text', text);
	if (text.indexOf('{{inside}}') === -1) {
		return callback(null, tampaxParse(text, s));
	}
	fs.readFile(s.file, 'utf-8', (err, data) => {
		if (err) {
			return callback(err);
		}
		result = data.toString().replace(/[\n\r]/g, '').trim();
		console.log(result);
		return callback(null, tampaxParse(text, s));
	}
	);
};

module.exports = getContent;
