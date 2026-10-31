# Settings for the whole project. Per-file flags belong here, not in scripts.
switch("styleCheck", "error")
# begin Nimble config (version 2)
--noNimblePath
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config
