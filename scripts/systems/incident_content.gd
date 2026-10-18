class_name IncidentContent
extends RefCounted
## Installs the "content" sections of data/incidents.json and data/incidents/*.json (buffs, interactions, objects, object_interactions in
## ContentMerge format) into the shared tables. Idempotent. SysContent.install_all() calls it, so every game and test that installs the
## systems content gets the injured / sick / grief buffs, graves and urns.

static func install() -> void:
	IncidentDefs.ensure()
	ContentMerge.install(IncidentDefs.content)
	HealthContent.install()
