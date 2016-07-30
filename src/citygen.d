module dmud.citygen;

import std.algorithm;
import std.format;
import std.math;
import std.random;
import std.stdio;

import dmud.domain;

struct Point {
	long x, y;
	string toString() { return "(%s, %s)".format(x, y); }
}

Zone makeCity() {
	auto rnd = Mt19937(112);
	// Choose the size of the city.
	auto radius = uniform(60, 100);
	auto rVariance = radius / 10;
	auto bounds = (radius + rVariance + 5) * 2;
	auto roomsRaw = new Room[bounds * bounds];
	//auto rooms = roomsRaw.sliced(bounds, bounds);

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
	writef(`<svg width="%s" height="%s" xmlns="http://www.w3.org/2000/svg">
	<path d="M `, bounds, bounds);
	auto off = bounds / 2 - 1;
	foreach (i, tower; towers) {
		if (i > 0) {
			writef(" L ");
		}
		writef("%s %s", tower.x + off, tower.y + off);
	}
	writeln(` Z" fill="blue" stroke="black"/>
</svg>`);
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
