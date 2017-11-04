<p align="center">
  <img src="icon/logo.svg" height="64">
  <h3 align="center">winegold</h3>
  <p align="center">An open-source drag and drop tool built with web technology<p>
  <p align="center"><a href="https://github.com/sindresorhus/xo"><img src="https://img.shields.io/badge/code_style-XO-5ed9c7.svg" alt="XO code style"></a></p>
</p>

**This tool is a WIP, he is not really usable right now.**

## Use winegold

![demo of winegold app](test/demo.gif)

Yes, I expected to be simple as this example.

One drag and drop, detecting what to do with this file. Or asking what you want to do with the files you've just dragged.

## Everything is script

We want to put file into the center of everything. 

For this example, here is the script you describing how everthing works :

```yaml

name: Convert to mobi

trigger :
  fileExtension:
   - pdf
   - epub

cmd:
  exec: ebook-convert <input> <output>.mobi --verbose

autolaunch: true

```

To understand, this script executes the shell command ebook-convert when a PDF or EPUB is found, and convert it to mobi.

This script auto launch the command when file is dragged.

As you can see, we using YAML to provide a **human readable  kind of file**.

You can add your own script by dragging a script called `"myscript.add.yml"`. This action adds a trigger and a command for your own needs.

[Read the script documentation](docs/script.md)

## Get winegold

**[Download the latest release](https://winegold.com/download)** (macOS only)


## Contribute

1. [Fork](https://help.github.com/articles/fork-a-repo/) this repository to your own GitHub account and then [clone](https://help.github.com/articles/cloning-a-repository/) it to your local device
2. Install the dependencies: `npm install`
3. Build the code and watch for changes: `npm run dev`
4. Run the app: `npm start`

To make sure that your code works in the finished app, you can generate the binary:

```
$ yarn dist
```

After that, you'll see the binary in the `dist` folder :smile:


