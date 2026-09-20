#include "../../define.as"


/*
 * Custom (denysfast/bar-game): shared state between managers.
 * Positions of own factories = "base" anchors for script-driven builds (anti-nukes, shields).
 */
namespace Base {

array<AIFloat3> positions;

void Add(const AIFloat3& in pos)
{
	for (uint i = 0; i < positions.length(); ++i) {
		if (positions[i].SqDistance2D(pos) < 600.f * 600.f)
			return;  // same base cluster
	}
	positions.insertLast(pos);
}

}  // namespace Base
