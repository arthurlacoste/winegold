// Removed scripts when needed

const {app} = require('electron');
const path = require('path');
const fs = require('fs-extra');

const pathsToDestruct = [path.join(app.getPath('appData'), 'winegold/scripts'),
	path.join(app.getPath('appData'), 'winegold/config.json')];

pathsToDestruct.forEach(f => {
	fs.removeSync(f);
	console.log('Remove ' + f);
});

app.exit();
