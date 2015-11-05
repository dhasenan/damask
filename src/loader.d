module dmud.loader;

import dmud.domain;
import dmud.player;

import std.json;

World load(string path) {
	auto world = new World();
	auto room1 = new Room();
	room1.description = "A fuzzy sort of room.";
	room1.id = "/tmp/r1";
	room1.name = "Fuzzy!";
	auto zone1 = new Zone();
	zone1.rooms = [room1];
	world.startingRoom = room1;
	world.zones[zone1.id] = zone1;
	return world;
}
