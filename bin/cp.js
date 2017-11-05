#!/usr/bin/env node

const path = require('path');
const fs = require('fs-extra');
const config = require('../src/config');

const BUILD_PATH = path.join(config.ROOT_PATH, 'build');
const SRC_PATH = path.join(config.ROOT_PATH, 'src');

console.log('Build: copying src/ to build/...');

fs.copy(SRC_PATH, BUILD_PATH)
  .then(() => {
	console.log('Done!');
	process.exit();
})
  .catch(err => console.log(err));
