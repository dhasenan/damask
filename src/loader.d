module dmud.loader;

import dmud.domain;
import dmud.player;

import std.json;

unittest {
	import std.string;

	assert("foo" == "  foo  ".strip);
}

World load(string path) {
	auto world = new World();
	auto room1 = new Room();
	room1.description = "A fuzzy sort of room.";
	room1.id = "/tmp/r1";
	room1.name = "Fuzzy!";
	auto room2 = new Room();
	room2.description = "A sharp and steely room.";
	room2.id = "/tmp/r2";
	room2.name = "Fuzzy!";

	Exit e = {
		room2,
		"/tmp/r2",
		"east",
		["e"]
	};
	room1.exits ~= e;

	Exit w = {
		room1,
		"/tmp/r1",
		"west",
		["w"]
	};
	room2.exits ~= w;

	auto zone1 = new Zone();
	zone1.rooms = [room1, room2];
	world.startingRoom = room1;
	world.zones[zone1.id] = zone1;
	return world;
}
