module dmud.citygen;

import std.algorithm;
import std.format;
import std.math;
import std.random;
import std.stdio;

import dmud.component;
import dmud.domain;

struct Point {
	long x, y;
	string toString() { return "(%s, %s)".format(x, y); }

	double dist(const ref Point other) {
		auto dx = x - other.x;
		auto dy = y - other.y;
		return (dx^^2 + dy^^2) ^^ 0.5;
	}

	void findNeighbors(ref Point[8] p) {
		p[0] = Point(x - 1, y - 1);
		p[1] = Point(x - 1, y);
		p[2] = Point(x - 1, y + 1);
		p[3] = Point(x, y - 1);
		p[4] = Point(x, y + 1);
		p[5] = Point(x + 1, y - 1);
		p[6] = Point(x + 1, y);
		p[7] = Point(x + 1, y + 1);
	}
}

/// A square array with *centered* coordinates
struct Square(T) {
	private {
		int _radius;
		int _off;
		int _dim;
		T[] _data;
	}

	this(int radius) {
		_radius = radius;
		// We want enough room to hold a center point, {radius} elements around, plus a margin of one.
		_dim = (_radius + 1) * 2 + 1;
		// how to get to the center
		_off = _radius + 2;
		_data = new T[_dim * _dim];
	}

	private long _index(long x, long y) {
		return (x + _off) * _dim + y + _off;
	}

	T opIndex(long x, long y) {
		return _data[_index(x, y)];
	}

	T opIndexAssign(T item, long x, long y) {
		return _data[_index(x, y)] = item;
	}

	T opIndexAssign(T item, Point p) {
		return _data[_index(p.x, p.y)] = item;
	}

	T opIndex(Point p) {
		return _data[_index(p.x, p.y)];
	}

	int opApply(int delegate(Point, T) dg) {
		for (long x = -_radius - 1; x <= _radius; x++) {
			for (long y = -_radius - 1; y <= _radius; y++) {
				auto p = Point(x, y);
				int a = dg(p, this[p]);
				if (a) return a;
			}
		}
		return 0;
	}
}

unittest {
	auto s = Square!(int)(5);
	s[1, 2] = 4;
	assert(s[1, 2] == 4);
	assert(s[-1, -2] == 0);  // default
	s[-5, -5] = 3;
	assert(s[-5, -5] == 3);
	s[-3, -5] = 3;
	assert(s[-3, -5] == 3);
	s[Point(4, -2)] = 188;
	assert(s[4, -2] == 188);
	assert(s[Point(4, -2)] == 188);
	s[0, 0] = -14;
	assert(s[0, 0] == -14);
}

Zone makeCity() {
	auto cm = ComponentManager.instance;
	auto rnd = Mt19937(112);
	// Choose the size of the city.
	auto radius = uniform(60, 100);
	auto rVariance = radius / 10;
	auto rooms = Square!Entity(radius + rVariance);

	// Pick towers for each Kdrant.
	Point[] towers;
	auto segments = uniform!"[]"(4, 8, rnd);
	auto region = PI * 2 / segments;
	for (int i = 0; i < segments; i++) {
		auto start = region * i;
		auto end = region * (i + 1);
		auto angle = uniform!"[]"(start, end, rnd);
		auto dist = uniform!"[]"(radius - rVariance, radius + rVariance);
		auto tower = toCoords(angle, dist);
		writefln("tower %s is between %s and %s radians -> %s radians, point %s", i, start, end, angle,
				tower);
		towers ~= tower;
	}

	// Pick a few additional towers.
	auto extraTowers = uniform!"[]"(2, 3);
	for (int i = 0; i < extraTowers; i++) {
		auto angle = uniform!"[]"(0, PI * 2, rnd);
		auto dist = uniform!"[]"(radius - rVariance, radius + rVariance);
		towers ~= toCoords(angle, dist);
	}
	towers.sort!((a, b) => atan2(cast(real)a.x, cast(real)a.y) < atan2(cast(real)b.x, cast(real)b.y));

	// TODO: prune towers producing bad angles

	// Add towers to the map.
	foreach (i, tower; towers) {
		auto e = cm.next;
		auto r = e.add!Room;
		auto room = e.add!MudObj;
		room.name = "Tower %s".format(i + 1);
		room.description = "A mighty tower named %s.".format(i + 1);
		rooms[tower] = e;
	}

	// Add walls.
	Point[8] neighbors;
	foreach (i, tower; towers) {
		auto targetIndex = (i + 1) % towers.length;
		auto target = towers[targetIndex];
		auto curr = tower;
		while (curr != target) {
			curr.findNeighbors(neighbors);
			Point best;
			double shortest = double.infinity;
			foreach (neighbor; neighbors) {
				auto d = neighbor.dist(target);
				if (d < shortest) {
					shortest = d;
					best = neighbor;
				}
			}
			curr = best;
			if (curr == target) break;

			auto e = cm.next;
			auto r = e.add!Room;
			auto room = e.add!MudObj;
			room.name = "City Wall";
			room.description = "A section of city wall between Tower %s and Tower %s".format(i + 1, targetIndex + 1);
			rooms[curr] = e;
		}
	}


	auto f = File("/home/dhasenan/foo.svg", "w");
	f.writef(`<svg width="%s" height="%s" xmlns="http://www.w3.org/2000/svg">
			<path d="M `, radius * 2 + 10, radius * 2 + 10);
	auto off = radius + 2;
	writeln(off);
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
	return null;
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
