class_name HospitalVisits
extends RefCounted
## The hospital is not a hangout: residents go there as patients (Hospital) or to visit a patient they know (housemate or acquaintance).

## {id, name} of a patient one of these folk knows, or {}.
static func patient_for(folk_ids: Array) -> Dictionary:
	for pid in Hospital.patients.keys():
		if folk_ids.has(int(pid)):
			continue
		for fid in folk_ids:
			var f = SysUtil.folk(int(fid))
			var p = SysUtil.folk(int(pid))
			var same_home: bool = f != null and p != null and int(f.household_id) == int(p.household_id) and int(f.household_id) > 0
			if same_home or RelationshipService.knows(int(fid), int(pid)):
				return {"id": int(pid), "name": CrimePerson.name_of(int(pid))}
	return {}
