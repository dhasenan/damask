module dmud.citygen;

import std.algorithm;
import std.exception;
import std.format;
import std.math;
import std.random;
import std.stdio;

import dmud.component;
import dmud.domain;
import dmud.util;

enum WALL_HEIGHT = 3;

Entity makeCity(bool assignStartRoom = true) {
	auto cm = ComponentManager.instance;
	auto rnd = Mt19937(112);
	// Choose the size of the city.
	auto radius = uniform(60, 100, rnd);
	auto rVariance = radius / 10;
	auto rooms = Cube!Entity(radius + rVariance);
	auto zoneEntity = cm.next;
	auto zone = zoneEntity.add!Zone;

	// Pick towers for each Kdrant.
	Point[] towers;
	auto segments = uniform!"[]"(4, 8, rnd);
	auto region = PI * 2 / segments;
	for (int i = 0; i < segments; i++) {
		auto start = region * i;
		auto end = region * (i + 1);
		auto angle = uniform!"[]"(start, end, rnd);
		auto dist = uniform!"[]"(radius - rVariance, radius + rVariance, rnd);
		auto tower = toCoords(angle, dist);
		towers ~= tower;
	}

	// Pick a few additional towers.
	auto extraTowers = uniform!"[]"(2, 3, rnd);
	for (int i = 0; i < extraTowers; i++) {
		auto angle = uniform!"[]"(0, PI * 2, rnd);
		auto dist = uniform!"[]"(radius - rVariance, radius + rVariance, rnd);
		towers ~= toCoords(angle, dist);
	}
	towers.sort!((a, b) => atan2(cast(real)a.x, cast(real)a.y) < atan2(cast(real)b.x, cast(real)b.y));

	// TODO: prune towers producing bad angles

	// Add towers to the map.
	foreach (i, tower; towers) {
		auto e = cm.next;
		auto r = e.add!Room;
		r.zone = zoneEntity;
		auto room = e.add!MudObj;
		room.name = "Tower %s".format(i + 1);
		room.description = "A mighty tower named %s.".format(i + 1);
		r.localPosition = tower;
		rooms[tower] = e;
	}

	// Add walls.
	foreach (i, tower; towers) {
		auto targetIndex = (i + 1) % towers.length;
		auto target = towers[targetIndex];
		auto dist = tower.dist(target);
		auto dx = ((target.x - tower.x) / dist);
		auto dy = ((target.y - tower.y) / dist);
		// TODO(dhasenan): make this prefer ordinal exits rather than hard corners.
		// (For walls at certain angles, it tends to produce, say, a line going east,
		// then one south exit, then continues east...would be more natural with a
		// southeast exit instead.)
		Point lastPlaced = tower;
		for (double d = 0.5; d < dist; d += 0.5) {
			auto x = tower.x + (dx * d);
			auto y = tower.y + (dy * d);
			auto point = Point(lrint(x), lrint(y), WALL_HEIGHT);
			if (rooms[point] != None) {
				if (point != lastPlaced) {
					auto k = rooms[point].get!Room;
					auto v = rooms[lastPlaced].get!Room;
					if (!k.dig(v, true)) {
						throw new Exception("failed to dig from %s to %s".format(k.localPosition, v.localPosition));
					}
				}
				lastPlaced = point;
				continue;
			}

			assert(lastPlaced.dist(point) < 1.5,
					"'adjacent' wall segments %s and %s too far (between towers %s and %s) -- raw point (%s, %s)".format(lastPlaced, point, tower, target, x, y));

			assert(lastPlaced.dist(point) >= 1.0, "tried to place two things on same point");
			auto e = cm.next;
			auto r = e.add!Room;
			r.zone = zoneEntity;
			r.localPosition = point;
			auto room = e.add!MudObj;
			room.name = "City Wall";
			room.description = "A section of city wall between Tower %s and Tower %s".format(i + 1, targetIndex + 1);
			rooms[point] = e;

			// Make an exit.
			auto last = rooms[lastPlaced];
			if (last != None && last != e) {
				if (!r.dig(last.get!(Room), true)) {
					throw new Exception("failed to dig from %s to %s".format(point, lastPlaced));
				}
			}

			lastPlaced = point;
		}
	}

	if (assignStartRoom) {
		auto w = world.get!World;
		w.startingRoom = rooms.nonDefaults.front;
	}

	auto f = File("/home/dhasenan/foo.svg", "w");
	f.writef(`<svg width="%s" height="%s" xmlns="http://www.w3.org/2000/svg">
			<path d="M `, radius * 2 + 10, radius * 2 + 10);
	auto off = radius + 2;
	foreach (i, tower; towers) {
		if (i > 0) {
			f.writef(" L ");
		}
		assert(tower.x + off > 0, tower.toString);
		assert(tower.y + off > 0, tower.toString);
		f.writef("%s %s", tower.x + off, tower.y + off);
	}
	f.writeln(` Z" fill="#eeeeaa" stroke="black"/>`);
	foreach (p, e; rooms) {
		if (e == None) {
			continue;
		}
		assert(p.x + off > 0, p.toString);
		assert(p.y + off > 0, p.toString);
		f.writefln(`	<circle cx="%s" cy="%s" r="0.5" fill="red"/>`, p.x + off, p.y + off);
	}
	f.writeln(`</svg>`);

	return zoneEntity;
}

unittest {
	import std.conv;
	auto p = toCoords(0, 100);
	assert(p.x == 100, p.toString);
	assert(p.y == 0);

	p = toCoords(PI/2, 100);
	assert(p.x == 0, p.toString);
	assert(p.y == -100, p.toString);

	p = toCoords(PI, 100);
	assert(p.x == -100, p.toString);
	assert(p.y == 0, p.toString);

	p = toCoords(PI * 1.5, 100);
	assert(p.x == 0, p.toString);
	assert(p.y == 100, p.toString);

	p = toCoords(PI * 0.25, 100);
	assert(p.x == 71, p.toString);
	assert(p.y == -71, p.toString);
}

double angleOf(Point p) {
	auto a = atan2(cast(real)p.x, cast(real)p.y);
	if (a < 0) {
		a += PI;
	}
	return a;
}

Point toCoords(double angle, double length) {
	Point p;
	p.z = WALL_HEIGHT;
	p.x = abs(lrint(cos(angle) * length));
	p.y = abs(lrint(sin(angle) * length));
	if (angle > PI * 0.5 && angle <= 1.5 * PI) {
		// left half
		p.x = -p.x;
	}
	if (angle > 0 && angle <= PI) {
		// bottom half
		p.y = -p.y;
	}
	return p;
}
