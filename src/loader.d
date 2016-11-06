module dmud.loader;

import dmud.component;
import dmud.db;
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

void load(Db db, ComponentManager cm) {
  // TODO
}

void save(Db db, ComponentManager cm) {
  db.startTx();
  scope(exit) db.endTx();
  foreach (entity; cm.entities) {
    foreach (component; cm.components(entity)) {
      db.save(component);
    }
  }
}
