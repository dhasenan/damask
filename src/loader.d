module dmud.loader;

import dmud.component;
import dmud.domain;
import dmud.player;

import jsonizer;

import std.algorithm;
import std.datetime;
import std.experimental.logger;
import std.file;
import std.json;
import std.string;
@safe:

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
