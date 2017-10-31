const fs = require('fs-extra');
const tampax = require('tampax');

// Const inside = '';
let result = '';

function tampaxParse(text, s) {
	const args = {
		file: s.fileFormated,
		inside: result
	};
	return (tampax(text, args));
}

const getContent = function (text, s, callback) {
	if (text.indexOf('{{inside}}') === -1) {
		const tp = tampaxParse(text, s);
		callback(null, tp);
	} else {
		fs.readFile(s.file, 'utf-8', (err, data) => {
			if (err) {
				callback(err);
			} else {
				result = data.toString();
				const tp = tampaxParse(text, s);
				callback(null, tp);
			}
		}
	);
	}
};

module.exports = getContent;
