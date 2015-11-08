module dmud.loader;

import dmud.domain;
import dmud.log;
import dmud.player;

import leveldb;

import std.algorithm;
import std.datetime;
import std.file;
import std.json;
import std.string;

unittest {
	import std.string;

	assert("foo" == "  foo  ".strip);
}

World loadAll(string p) {
	// Directory layout:
	// mymud/
	//   prod/
	//     world.db
	//     players.db
	//     houses.db
	//     zones/
	//       zone1_aleria.db
	//       zone2_khavlad.db
	//       zone3_thuanil.db
	//  staging/
	//    # same as above
	//  backups/
	//    prod/
	//    staging/
	if (!p.exists) {
		logger.infof("You asked to load a world from %s, but there's no world there. I'm generating " ~
				"a tiny one from scratch and saving it there. " ~
				"If you think you are receiving this message in error, make sure that you " ~
				"configured your MUD with the right paths and the world files you expected are there. " ~
				"Note that the paths are case sensitive -- /foo/bar is not the same as /Foo/Bar.", p);
		auto world = makeTestWorld();
		save(world, p);
		return world;
	}
	auto db = new DB(new Options, p);
	string val;
	if (!db.get("world", val)) {
		logger.fatalf("You asked to load a world from %s. There was a database there, but it doesn't " ~
				"contain a world, as far as I can tell. Since I don't know what the thing that *is* " ~
				"there currently has, I'm not going any further. If you don't expect a world to be " ~
				"there, you can just delete the database.", p);
		throw new Exception("Failed to read world from database. See logfile for details.");
	}

	auto j = parseJSON(val);
	auto w = new World();
	with (w) {
		name = j["name"].str;
		banner = j["banner"].str;
		auto it = db.iterator;
		it.seek("news");
		foreach (k, v; it) {
			if (!k.as!string().startsWith("news")) {
				break;
			}
			auto s = v.as!string;
			auto ni = new NewsItem();
			auto j = s.parseJSON;
			ni.id = k.as!string;
			ni.news = j["news"].str;
			ni.date = SysTime.fromISOString(j["date"].str);
			news ~= ni;
		}
		news.sort!((a, b) => a.date < b.date);
	}
	return w;
}

void save(World world, string p) {
}

World makeTestWorld() {
	auto world = new World();
	with (world) {
		name = "Nameless Mud";
		banner = `
          -- The Nameless Mud --
-- featuring sporks, goats, and intrigue? --
               YOU DECIDE!
`;
		news = [new NewsItem(Clock.currTime, "Welcome to your new MUD!\n\n" ~
				"If you are the first to log in, you are the admin. If not, this is a work in progress; " ~
				"give it a bit for the creators to get things under control.\n\n" ~
				"Use the 'help' command for help. If you are a creator, try 'help creator' or 'help " ~
				"admin'.")];
	}
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
