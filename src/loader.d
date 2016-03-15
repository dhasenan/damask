module dmud.loader;

import dmud.component;
import dmud.domain;
import dmud.player;

import couch;
import url;
import jsonizer;

import std.algorithm;
import std.datetime;
import std.experimental.logger;
import std.file;
import std.json;
import std.string;

void loadAll(URL couchdb, string database) {
	auto client = new CouchClient(couchdb);
	auto db = client.database(database);
	if (!client.databases.any!(x => x == database)) {
		info("You asked to load a world from %s, but there's no world there. I'm generating " ~
				"a tiny one from scratch and saving it there. " ~
				"If you think you are receiving this message in error, make sure that you " ~
				"configured your MUD with the right paths and the world files you expected are there. " ~
				"Note that the paths are case sensitive -- /foo/bar is not the same as /Foo/Bar.", database);
		db.createDatabase();
		makeTestWorld;
		saveWorld;
		return;
	}

	// We save everything about the world. Everything.
	// That means we can just load everything out of the database as is.

	foreach (doc; db.allDocs) {
		inflate(doc);
	}
}

void saveWorld() {
	throw new Exception("not implemented");
}

void inflate(JSONValue doc) {
	auto comp = doc.fromJSON!Component;
	if (comp) {
		ComponentManager.instance.add(comp.entity, comp);
	} else {
		warning("unrecognized component " ~ doc.toPrettyString);
	}
	// This is where we'll start up all the scripts.
}

void save(World world, string p) {
}

void makeTestWorld() {
	auto c = ComponentManager.instance;
	auto w = world.add!World;
	w.name = "Nameless Mud";
	w.banner = `
          -- The Nameless Mud --
-- featuring sporks, goats, and intrigue? --
               YOU DECIDE!
`;
	auto allNews = world.add!AllNews;
	allNews.news = [new NewsItem(Clock.currTime, "Welcome to your new MUD!\n\n" ~
			"If you are the first to log in, you are the admin. If not, this is a work in progress; " ~
			"give it a bit for the creators to get things under control.\n\n" ~
			"Use the 'help' command for help. If you are a creator, try 'help creator' or 'help " ~
			"admin'.")];

	auto room1 = c.next;
	w.startingRoom = room1;
	auto room2 = c.next;
	{
		auto r1 = c.add(room1, new Room);
		auto m1 = c.add(room1, new MudObj);
		m1.description = "A fuzzy sort of room.";
		m1.name = "Fuzzy!";
		Exit ex = {
			room2,
			"east",
			["e"]
		};
		r1.exits ~= ex;
	}
	{
		auto r1 = c.add(room2, new Room);
		auto m1 = c.add(room2, new MudObj);
		m1.description = "A sharp and steely room.";
		m1.name = "Ouch!";
		Exit ex = {
			room1,
			"west",
			["w"]
		};
		r1.exits ~= ex;
	}
}
