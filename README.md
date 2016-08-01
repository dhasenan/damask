Damask MUD
==========

This is a MUD engine! It's got some reasonable goals and some far-flung goals.


Current status
--------------
The MUD isn't currently useful for anything.


Dependencies
------------
You must install the sqlite development packages or otherise acquire a copy of the sqlite3 static
library. On Ubuntu:

    sudo apt-get install libsqlite3-dev


Reasonable goals
----------------
I want Damask to feature:

* online creation
* player housing
* sensible scripting
* support for large worlds (100,000 rooms)
* support for large player bases (1,000 simultaneous players)
* optional full persistence

"Full persistence" won't be desirable for many people. It means that, if I walk up to the Broken
Drum and kill Stren Withel, Stren Withel is *dead*, and stays dead even when I reboot the server. If
I drop a sword on the ground, that sword isn't going to disappear on the next reboot.

Player housing is, largely, a controlled subset of full persistence, where items are persistent in a
limited area.


Far-flung goals
---------------
These are goals that are difficult to achieve or that I don't quite know how to achieve:

* procedurally generated worlds (though I won't match Dwarf Fortress)
* NPCs behaving like real people


License
-------
This project is licensed under the Apache License, Version 2.0.
