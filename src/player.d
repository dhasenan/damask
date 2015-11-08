module dmud.player;

import core.thread;
import std.concurrency;
import std.digest.sha;
import std.experimental.logger;
import std.string;
import std.stdio;
import std.typecons;
import std.uni;

import dmud.commands;
import dmud.domain;
import dmud.container;
import dmud.log;
import dmud.telnet_socket;
import dmud.time;

class PlayerInputBehavior : Behavior {
	Queue!string commands;
	Behavior child;
	Command next(Time now) { return null; }
}

abstract class InputProcessor {
	private Fiber _runFiber;
	
	final void run(TelnetSocket telnet) {
		assert(!!scheduler);
		scheduler.spawn({
				_runFiber = Fiber.getThis();
				doRun(telnet);
				_runFiber = null;
			});
	}
	
	void interrupt() {
		throw new Exception("this option is not yet implemented");
	}
	
	abstract void doRun(TelnetSocket telnet);
}

auto splitOnce(string str) {
	foreach (int i, dchar d; str) {
		if (d.isWhite) {
			return tuple!("head", "tail")(str[0..i], str[i..$].stripLeft);
		}
	}
	return tuple!("head", "tail")(str, "");
}

class PlayerBehavior : Behavior {
	Player player;
	TelnetSocket telnet;

	this(Player p, TelnetSocket sock) {
		player = p;
		telnet = sock;
	}

	void run() {
		logger.infof("starting player behavior");
		writeln("starting player behavior!!");
		mainLoop:
		while (!telnet.closed) {
			auto line = telnet.readLine.stripRight;
			auto parts = line.splitOnce;
			logger.infof("player command: [%s] [%s]", parts.head, parts.tail);
			auto tail = parts.tail.strip.toLower;

			// Room exits take priority.
			if (player.room) {
				logger.info("checking for exits");
				foreach (exit; player.room.exits) {
					logger.infof("checking exit toward %s", exit.name);
					if (exit.identifiedBy(parts.head)) {
						logger.infof("moving player to room %s", exit.target.id);
						player.room = exit.target;
						player.write(player.room.lookAt(player));
						logger.info("player has been moved");
						telnet.writeln("");
						continue mainLoop;
					}
				}
				logger.info("no matching exit");
			}

			// TODO: aliases
			// TODO: item- and room-specific commands
			auto commandsPtr = parts.head in Command.allCommands;
			if (!commandsPtr) {
				telnet.writeln("Huh?");
				telnet.writeln("");
				continue;
			}
			Command selected;
			foreach (cmd; *commandsPtr) {
				if (cmd.applicable(player)) {
					if (selected) {
						// Two applicable commands. What do?
						logger.errorf("Found two overlapping commands for name '%s'. Player '%s' at room '%s' " ~
							"experienced this problem. Command 1: %s. Command 2: %s.",
							parts.head, player.name, player.room.id, selected.id, cmd.id);
						telnet.writeln("There are two or more commands matching your input.");
						telnet.writeln("I'm really confused about this, and I'm logging your situation for devs " ~
							"to investigate.");
						telnet.writeln("Hold tight, maybe try again in another room. Sorry!");
					}
					selected = cmd;
				}
			}
			if (selected) {
				selected.act(player, parts.tail);
				telnet.writeln("");
			}
			// TODO: how long do we yield *for*?
			// Need to create a scheduler, command tells how long it takes, etc.
			scheduler.yield;
		}
	}
}

class WelcomeProcessor : InputProcessor {
	Player player;
	InputProcessor next;
	
	override void doRun(TelnetSocket telnet) {
		while (!telnet.closed) {
			telnet.write("Enter your character's name, or \"new\" for a new character: ");
			auto first = telnet.readLine;
			if (first != first.strip) {
				writeln("error: readLine didn't strip");
			}
			if (first == "quit") {
				writeln("quitting");
				telnet.close();
				return;
			}
			if (first == "new") {
				registerNewPlayer(telnet);
				return;
			}
			auto p = first in Player.byName;
			if (!p) {
				telnet.writeln(format("Sorry, no player by that name exists."));
				continue;
			}
			auto player = *p;
			telnet.write(format("Enter password for %s: ", first));
			while (!telnet.closed) {
				auto pass = telnet.readLine;
				if (player.passwordEqual(pass)) {
					break;
				}
				telnet.writeln("Sorry, that's not the right password. Try again.");
			}
			// You've logged in! \o/
			telnet.writeln(format("Welcome back to Damask, %s.", player.name));
			startPlayer(player, telnet);
			return;
		}
	}

	void startPlayer(Player player, TelnetSocket telnet) {
		this.player = player;
		auto behavior = new PlayerBehavior(player, telnet);
		player.behavior = behavior;
		player.telnet = telnet;
		if (player.room is null) {
			player.room = World.current.startingRoom;
		}
		scheduler.spawn(&behavior.run);
	}
	
	void registerNewPlayer(TelnetSocket telnet) {
		string name;
		telnet.write("What name do you want? ");
		while (!telnet.closed) {
			name = telnet.readLine.strip;
			if (name in Player.byName) {
				telnet.write("That name is already taken. Try again. ");
				continue;
			}
			break;
		}
		telnet.writeln(format("Okay, we're calling you %s.", name));
		string pass;
		while (!telnet.closed) {
			// TODO: validation -- no punctuation, numbers, etc
			telnet.write("Enter your password: ");
			pass = telnet.readLine();
			telnet.write("Enter your password again: ");
			auto pass2 = telnet.readLine();
			if (pass == pass2) {
				break;
			} else {
				telnet.writeln("Sorry, your passwords didn't match.");
			}
		}
		auto p = new Player();
		p.password = pass;
		p.name = name;
		Player.byName[name] = p;
		telnet.writeln(format("Welcome to Damask, %s.", name));
		startPlayer(p, telnet);
	}
	
	void gmcp(string raw) {
		
	}
}

/// A player. Not necessarily in the game right now.
class Player : Mob {
	static Player[string] byName;
	ubyte[] passwordHash;
	bool admin;
	bool playing;
	TelnetSocket telnet;

	static this() {
		// Testing only!
		auto p = new Player();
		p.name = "Todd";
		p.password = "pass";
		byName["todd"] = p;
	}

	void password(string value) {
		auto hash = sha256Of(value);
		passwordHash.length = hash.length;
		passwordHash[0..$] = hash[0..$];
	}

	bool passwordEqual(string value) {
		auto hash = sha256Of(value);
		return hash[0..$] == passwordHash;
	}
	
	bool login(TelnetSocket socket, string username, string pass) {
		if (!name && !passwordHash) {
			password = pass;
			name = username;
			id = "/players/" ~ name;
			description = "A new player. Be gentle.";
			telnet = socket;
			return true;
		}
		if (name == username && passwordEqual(pass)) {
			this.telnet = socket;
			return true;
		}
		return false;
	}

	override void write(string value) {
		if (telnet) {
			telnet.write(value);
		}
	}

	override void writeln(string value) {
		if (telnet) {
			telnet.writeln(value);
		}
	}
}
