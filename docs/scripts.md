# Script Documentation


## Inside the file

To add a file to winegold, simply drop a file called `"myscript.add.yml"`.

### name

{string} **optional** The name of the script, display in the Process column.

Example:

```yaml
name: Convert to mobi
```

### trigger

{Object} **required** One of these condition needed to be true.

* `fileExtension` {string|Array} File extension. Search each string in the fullpath. Not only the extension.

```yaml
trigger :
  fileExtension:
   - pdf
   - epub
```

### before

{Object} **optional** Run theses commands before `cmd`, start cmd after it, and stop if there is an error.

* `exec` {string} execute a command in a shell.
* `eval` {string} Execute javascript in a node child process.

```yaml
before:
  exec: echo hello
```

### cmd

{Object} **required** Main command, return a green validation if everything

* `exec` {string} execute a command in a shell.
* `eval` {string} Execute javascript in a node child process.

```yaml
cmd:
  eval: console.log('Really boring and useless string.')
```

### after

{Object} **optional**

* `exec` {string} execute a command in a shell.
* `eval` {string} Execute javascript in window, with an `eval()` function. You can edit interface if you want/need.

```yaml
after:
  eval: alert('Really annoying and useless string.')
```
## Tags

You can use some tag to insert in your commands :

### {{file}}

Represent the full path & file from your file, edited to use it as a parameter in a shell.

```yaml
trigger:
  fileExtension: .js
cmd:
  exec: node <file>
```

This example launch node if you drag a js file on the app.
