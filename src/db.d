module dmud.db;

import std.algorithm;
import std.array;
import std.json;

import d2sqlite3;
import jsonizer.fromjson;
import jsonizer.tojson;

import dmud.component;

@trusted:

struct PlayerInfo {
	string name;
	string pbkdf2;
	Entity entity;
}

class Db {
	private {
		Database _db;
		Statement _getUser;
		// get component by entity + type
		Statement _getComponent;
		// get components by entity
		Statement _getComponents;
		// update or insert component
		// provided as upsert because simplicity
		Statement _upsertComponent;
		// insert (do not update) player
		// provided as insert because security
		Statement _insertUser;
		// update player's password only
		// they aren't allowed to do anything else
		Statement _updateUserPassword;
	}

	this(string path) {
		this._db = Database(path);
	}

	void init() {
		// Simple schema, no?
		_db.execute(`CREATE TABLE IF NOT EXISTS user (name text, pbkdf2 text, entity integer, primary key (name))`);
		_db.execute(`CREATE TABLE IF NOT EXISTS component (entity integer, type text, data text, primary key (entity, type))`);
		_getUser = _db.prepare(`SELECT name, pbkdf2, entity FROM user WHERE name = :name`);
		_getComponents = _db.prepare(`SELECT entity, type, data FROM component WHERE entity = :entity`);
		_getComponent = _db.prepare(`SELECT entity, type, data FROM component WHERE entity = :entity AND type = :type`);
		_upsertComponent = _db.prepare(`INSERT OR REPLACE INTO component (entity, type, data) VALUES (:entity, :type, :data)`);
		_insertUser = _db.prepare(`INSERT INTO user (name, pbkdf2, entity) VALUES (:name, :pbkdf2, :entity)`);
		_updateUserPassword = _db.prepare(`UPDATE user SET pbkdf2 = :pbkdf2 WHERE name = :name`);
	}

	auto getComponents(Entity entity) {
		scope(exit) _getComponents.reset;
		_getComponents.bind(":entity", entity.value);
		return _getComponents.execute()
			.map!((x) => fromJSON!Component(parseJSON(x["data"].as!string)))
			.array;
	}

	Component getComponent(Entity entity, string type) {
		scope(exit) _getComponent.reset;
		_getComponents.bind(":entity", entity.value);
		_getComponents.bind(":type", type);
		auto r = _getComponent.execute();
		if (r.empty) return Component.init;
		return fromJSON!Component(parseJSON(r.front["data"].as!string));
	}

	void save(const Component component) {
		if (!component.canSave) {
			return;
		}
		// We must cast away const here because jsonizer is not const-friendly.
		// https://github.com/rcorre/jsonizer/issues/27
		_upsertComponent.inject(component.entity.value, component.classinfo.name,
				(cast(Component)component).toJSON.toString);
	}

	PlayerInfo getUser(string name) {
		scope(exit) _getUser.reset;
		_getUser.bind(":name", name);
		auto res = _getUser.execute;
		if (res.empty) {
			return PlayerInfo.init;
		}
		return PlayerInfo(
				name,
				res.front["pbkdf2"].as!string,
				Entity(res.front["entity"].as!ulong));
	}

	void saveUser(string name, string pbkdf2, Entity entity) {
		_insertUser.bind(":name", name);
		import std.experimental.logger;
		infof("saving user %s with hashed pw %s", name, pbkdf2);
		_insertUser.bind(":pbkdf2", pbkdf2);
		_insertUser.bind(":entity", entity.value);
		_insertUser.execute;
		_insertUser.reset;
	}
}
