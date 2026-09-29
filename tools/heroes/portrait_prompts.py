import sys
VEH = set("armbull armmanni armmerl corgol correap corban cortrem legaskirmtank legaheattank legvcarry legmed armt4zeus legt4longinus".split())
LOW = set("armspid armsptk armt4olympus legt4starfall legsrail leghrk cortermite armfido corhrk cort4armageddon cort4bastion corsumo corcan".split())
COL = {"arm": "Armada blue", "cor": "Cortex red and orange", "leg": "Legion green and gold"}
def prompt(u):
    kind = "vehicle" if u in VEH else "robot"
    col = COL[u[:3]]
    if u in VEH:
        frame = "a heroic low three-quarter front close-up of the whole vehicle that fills the frame"
    elif u in LOW:
        frame = "a heroic low three-quarter front view of the whole machine, close-up, filling the frame"
    else:
        frame = "a heroic low camera angle, head-and-shoulders and upper body framing that fills the frame"
    return (f"Keep the exact {kind} from image1 unchanged in design: same silhouette, same armor plates, same weapons, "
            f"same paint colors and markings. Turn the picture into a dramatic hero portrait card for a sci-fi strategy game: "
            f"{frame}, cinematic rim light in {col}, glowing eyes and sensors, dark atmospheric battlefield background "
            f"with sparks, embers and smoke, painted sci-fi game art, high detail. No text, no letters, no frame.")
if __name__ == "__main__":
    print(prompt(sys.argv[1]))
