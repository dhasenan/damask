module dmud.loader;

import dmud.component;
import dmud.domain;
import dmud.log;
import dmud.player;

import leveldb;

import std.algorithm;
import std.datetime;
import std.file;
import std.json;
import std.string;

void loadAll(string p) {
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
		logger.info("You asked to load a world from {}, but there's no world there. I'm generating " ~
				"a tiny one from scratch and saving it there. " ~
				"If you think you are receiving this message in error, make sure that you " ~
				"configured your MUD with the right paths and the world files you expected are there. " ~
				"Note that the paths are case sensitive -- /foo/bar is not the same as /Foo/Bar.", p);
		makeTestWorld();
		//save(world, p);
		return;
	}
	auto db = new DB(new Options, p);
	string val;
	if (!db.get("world", val)) {
		logger.fatal("You asked to load a world from {}. There was a database there, but it doesn't " ~
				"contain a world, as far as I can tell. Since I don't know what the thing that *is* " ~
				"there currently has, I'm not going any further. If you don't expect a world to be " ~
				"there, you can just delete the database.", p);
		throw new Exception("Failed to read world from database. See logfile for details.");
	}

	auto j = parseJSON(val);
	with (world.add!World) {
		name = j["name"].str;
		banner = j["banner"].str;
		auto it = db.iterator;
		/*
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
			ni.date = parseDateAndTime(j["date"].str);
			news ~= ni;
		}
		news.sort!((a, b) => a.date < b.date);
		*/
	}
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
