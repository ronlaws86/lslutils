# Region crossings in Second Life
Problems and solutions

John Nagle
Animats
February, 2018

Revised March, 2018

# Executive summary
There are at least five separate problems in Second Life region crossing. 
These problems damage the user experience and make Second Life's huge seamless world
much less usable.  All of those problems can be fixed. Here's how.

# Background
The Second Life virtual world is divided into regions 256 meters
on a side. Large areas are built up from many such regions, yielding 
a virtual world with hundreds of square kilometers of area. This division
into regions is the great strength of Second Life. It allows building a
world of great size which appears almost seamless to the user. Most competing
virtual worlds are divided into limited areas. Second Life, unlike such systems,
can and has scaled geographically.

It's useful to think of each region as an island, with a gap between regions. Objects can
stick out over the edge of a region, but not very far. When a vehicle or avatar crosses
a region boundary, it briefly hangs off the edge of the region. It can start to fall if
there's nothing there to support it. Once the root location of a vehicle or avatar is
outside the region, it is teleported to the corresponding point in the next sim.
Vehicles with avatars on board are teleported without their avatars. Then the avatars
are teleported and re-seated on the vehicle. All this takes a second or two, and the
process is visible to the user. 

The user's viewer talks to all the servers displaying the regions currently visible.
The viewer creates the visual illusion that the regions are a seamless world.

## Teleports
When an avatar or vehicle moves from one region to another, there is
a handoff between the neighboring "sim" programs. Objects are active in only one
sim at a time. Teleporting an object involves freezing its state the losing sim, copying
information to the gaining sim, and starting its simulation on the gaining sim.
This generally works well.

The same teleport mechanism handles both user-requested teleports between distant locations and region crosses.
User-requested teleports come with animations and sound effects, but this is cosmetic.

Teleports can fail. They involve network communications between computers. When they fail, repeating the
teleport request will usually result in a successful teleport. 

**Failed region crossings are failed teleports.** Retrying the teleport can recover many failed region
crossings.

## Failed region crossings, or "half-unsits".
Many things can go visibly wrong in a region crossing, but most of them are corrected within a few seconds.
One kind of failure stops the user dead - the dreaded "half-unsit". The vehicle is successfully teleported across
the region crossing, but one or more of the passenger avatars don't make it. They're usually left hanging in
space, unable to move. Recovery usually requires logging out of Second Life. 

In that situation, the user can initiate a teleport manually. This moves the avatar, but if the avatar had
control of the vehicle, the users's control keys are still tied to the vehicle and won't move the avatar.
So the user usually has to log out and start over.

We've developed LSL scripts which can detect and recover from this situation. We teleport the avatar
to a spot next to the vehicle, using "llTeleportAgent". Then we re-seat the avatar on the vehicle,
using the "@sit" command in the RLV system. Back on the vehicle, the user can then drive away.

It's a bit surprising that this works. It shows that a "half-unsit" is simply a failed teleport.
Failed teleports can be retried. That's how to fix this. 

### Half-unsit recovery script
Within a vehicle script, a "half-unsit" is recoverable because the vehicle still has the
avatar as a child prim. But the avatar no longer has the vehicle as its root. This situation
exists momentarily during region crossings, so we have to check that it persists for a few
seconds to detect a half-unsit.

Once a half-unsit is detected, the script stops the vehicle. We don't want to be chasing
a runaway vehicle while trying to re-seat the avatar. Once stopped, the script gets
the vehicle location and selects an open space where the avatar can land.
The avatar is then teleported to the open space. 

That teleport might fail. So the script checks for arrival by measuring the distance
between the avatar and destination point. The teleport is repeated if necessary.

Once the avatar has arrived, the RLV system is used to perform a "force sit" 
operation to put the avatar back in the vehicle. The vehicle's state is then
set to a driveable state and control is returned to the user.

This works, but the user experience needs improvement. The half-unsit usually results in a bad
camera position. Teleport permission is required, which requires user interaction
every time they get on the vehicle. The teleport has all the usual sound and animation effects.
The use of RLV requires that the avatar wear an active RLV relay.  If the vehicle is in
an area which disallows object entry, the vehicle may disappear before the avatar is
re-seated. Despite all this, it's far better than the alternative, which is usually
logging out and losing the vehicle. 

The current version of the script for this is on Github, at 
https://github.com/John-Nagle/lslutils/blob/master/motorcycledrive.lsl

### Half-unsit prevention

Preventing half-unsit failures would be better than recovering from them. We've
made some progress towards doing that. The LSL script "changed" event reports
region changes, and for a vehicle, this reflects that the vehicle has crossed into
a new region. The passenger avatars may not have arrived yet. We can detect passenger
avatar arrival by checking for the avatar reporting the vehicle as its root prim.
So, as a preventive measure, we stop vehicle motion by the drastic measure of 
turning off "physics" mode on a region change. This freezes the vehicle in place.
The vehicle is held until the avatars arrive, then released. The typical delay
is 40-150ms. This usually prevents the vehicle from crossing a second region boundary
before the first region crossing has been entirely completed.

This is not perfect.  There are still get errors with a high-speed cross within about 3-4m of the
junction of four sims.
Further out than that,  Close to the junction, the change event and pause don't happen soon enough.
The next step is to try forcing a brief slowdown when a vehicle is headed very close to a region
corner. That's a rare event. 

#### When to slow down for a double region crossing

[Double region crossing closeness check](https://github.com/John-Nagle/lslutils/blob/master/nearcornercheck.svg)

The goal is to prevent the time between two region crossings from being too short.
That time is roughly proportional to the length of the red line segments in the drawing above.
We need to compute those lengths for each of the three possible trajectories, and use
the shortest one. 

Derivation (NEEDS CHECKING)

    Vehicle root at p, coords (p.x, p.y)
    Nearest region corner at q.
    Vehicle direction vector v.
    
    dp = p - q
    
    Need X and Y axis intercepts of dv in direction v.
    
    
    pos = dp + v * k                    Point plus unit vector*k
    pos.x = dp.x + v.x * k              Expand
    pos.y = dp.y + v.y * k
    let pos.x = 0                       Looking for Y intercept
    dp.x + v.x * k1 = 0
    v.x * k1 = -dp.x
    k1 = - dp.x / v.x
    pos1.y = dp.y + v.y * (-dp.x/v.x)
    
    let pos2.y = 0
    dp.y + v.y * k2 = 0
    v.y * k2 = -dp.y
    k2 = - dp.y / v.y
    pos2.x = dp.x + v.x * (-dp.y/v.y)
    
    distsq = pos1.x * pos1.x + pos2.y * pos2.y  Segment length squared
    
    Need to do this for the two vectors which represent reasonable turn bounds.
    So generate v from the vehicle velocity using two precomputed rotation
    matrices. This is all ordinary floating point arithmetic; no trig functions.
    
The vehicle speed at the first region cross has to be brought down to below about 2-3m/sec
before the first crossing if the minimum segment length above is below about 4 meters.
Those values will have to be set experimentally.
 
The effect is to cause heavy braking if the vehicle is headed almost straight for the junction
of four regions, and not otherwise. 
 
If the segment length is very large (more than 3 seconds at the current speed), it may
be possible to skip the freezing in place of the vehicle at the the region crossing at all.
This will require testing.

### Testing
This problem has been seen for years, but until we got some of the other problems
out of the way, was hard to recognize and debug.

It's hard to reproduce this problem quickly. Experience is that it comes up
about once or twice an hour with our test motorcycle. 
The most successful way we've found to 
reproduce it is with a rail car run past two closly spaced sim crossings.
Because the car is on rails, it's in the same place every time.
Even then, it appears that the sims must not have seen avatar or rail car
recently, within the last 10 minutes or so. Otherwise, the sim crossing 
goes smoothly, presumably because some information is cached.

Vehicles with more passengers increase the odds of a failure. 

We've been able to force failures under Linux by adding 1000ms of packet delay
to all network packets. The Linux command

    sudo tc qdisc add dev eth0 root netem delay 1000ms
    
will delay all packets by 1000ms.

    sudo tc qdisc del dev eth0 root
    
turns off the delay. With 1000ms delay, almost every double region crossing
will cause a half-unsit failure. At last, a repeatable test tool.

### Test motorcycle

![Test motorcycle](https://github.com/John-Nagle/lslutils/blob/master/testbike.jpg)

**Test motorcycle**

*This is an experimental bike and may have problems.* 

We usually leave a free motorcycle with these fixes parked at
Vallone/209/23/36. Look for a bike with yellow and black angled stripes.
This identifies our current test bike. Feel free to take a copy.
This bike also deals with the animation and camera problems mentioned below. 

It's been driven all over Heterocera and Kama City, usually around
20m/s, or 45mph. Don't bother slowing down for region crossings.

Use of this bike requires wearing an RLV relay which will allow a forced sit
to get fully automatic recovery from a half-unsit.
We use "DM2-Meter V3.027", which is intended for combat games. There's
a crate next to the parked bike which can be copied to get one. Once worn,
it brings up a HUD display at top center, allowing the RLV features to be
turned on and off. When that display is red, the RLV features are available.

When you get on the bike, it will ask for teleport permission. It uses that to
teleport you back to the bike if you come off at a region crossing.
Pressing PAGE DOWN will trigger a test of the teleport/resit sequence. It will be
triggered automatically should a half-unsit occur. Re-sitting is not yet reliable,
but if it doesn't work, get off the bike and get back on to reset. Report
problems to "animats" in Second Life. Video of problems would be appreciated.

This a test vehicle. That's why the yellow and black stripes. It tends to
go airborne at high speeds, and isn't useful for racing. But it will get
you around Second Life.  Try it and go drive some place.

### Half-unsit recovery as a fix to the sim system
Script-based recovery with a custom bike is a workaround for a bug in the underlying sim system.
The teleport retry and re-sit should be performed in the sim system. The main
fix required may simply be to detect teleport failures at region crossings and
retry them. This is a job for Linden Labs. 

The question has been raised in the Server User Group meeting of whether a fix of this
type should involve holding the vehicle stalled at the sim crossing until all
the avatars arrive. The system does not currently do this. At some crossings,
the vehicle keeps going and the avatar zips after it to catch up and re-seat.

As a suggestion, when a vehicle crosses a sim boundary, the existing behavior
is fine. But until the avatars catch up, the vehicle should not be allowed
to cross a second sim boundary. This will result in an additional stall at
rare double sim crossings, but fewer half-unsits. 

It would also be helpful, during a sim crossing, to keep the camera aimed at the
avatar's sit position, rather than at the avatar itself. Then it doesn't matter
as much that the avatars are still teleporting.  This
will reduce user disorientation, help prevent accidents due to bad
steering decisions, and improve the user experience.

## Other region crossing problems
There are at least five separate problems in region crossing. They all look
similar to the end user, and thus bug reports on them have been difficult to address.
Here we sort them out, discuss each separately, and provide solutions or workarounds
for them. The big one, the "half unsit" problem, is covered above.

## Velocity extrapolation errors
When a vehicle or avatar crosses between regions, its state is frozen for about 0.5 seconds
to, in the worst case, 10 seconds. About 1 second is typical. During this period, no 
object position update messages are sent to the viewer client. The viewer attempts to 
extrapolate the position during this dead time to give the user a better user experience.

The extrapolation is done by code intended for another purpose entirely - reducing 
network traffic by not sending object updates when the position can be calculated
from the previous update's position, velocity, angular velocity, and linear acceleration
values. This is a well known video game optimization borrowed from multiplayer first person shooters,
where information for bullets and other flying objects need be sent only when they are
fired and when they hit something. 

Using this algorithm during the freeze at a region crossing can produce grossly incorrect
visual results. The slightest movement glitch in the last update as an avatar leaves the
control of one sim will be amplified by the extrapolator into a huge error. Avatars and
vehicles roll over, go into the ground, and fly wildly into the air because of this.
This is disconcerting to users, some of whom are unable to drive vehicles because of this
effect. 

This bug results in only temporary mis-positioning. When the gaining sim sends
an object update message, the correct position is restored. 

We have implemented a solution to this problem in the open source Firestorm viewer.
See https://jira.phoenixviewer.com/browse/FIRE-21915

This change clips motion extrapolation at sim boundaries, preventing bogus predictions.
The freeze happening during sim handoff is represented as the avatar or vehicle stopping
during the region crossing. This appears to be a good solution for land vehicles.
The user experience at region crossing becomes much cleaner.

With this change, slow sailing vessels look somewhat different at crossings; they stop for a moment.
Flags continue to wave, and sounds continue, but the animated wake looks wrong for a 
few seconds. Before the change, there were sometimes worse artifacts, including the
boat sinking for a few seconds, and the boat being jerked backwards as the region crossing
completes. But often, in open water, the region crossing seemed seamless, because all
water looks the same and the jerk-back was invisible. Some work
on wake animation may be able to restore the illusion of seamless crossings.

This fix is on track for inclusion in a Firestorm beta version. Linden Labs is welcome
to copy the code.

## Animation shutdown
It is quite common for a vehicle rider animation to stop at a region crossing.
The default "sit" animation is then run. 
This can be fixed in vehicle scripts by detecting the region crossing, using
a "changed'" event, and then restarting the animation.

We check for a number of conditions after each region crossing - that the
avatar is close to their normal sit point, that the vehicle links to the
avatar and the avatar links back to the vehicle, and that all requested
animation permissions are available. There are moments during normal region handoffs
during which some of those conditions do not hold. Trying to do anything
from a script during those periods seems to have problems. Se we wait until 
the avatar/vehicle relationship is back to normal before proceeding.

Both this, and the camera fix below, are implemented in our test
motorcycles.

## Bogus camera movement
Big jumps in camera position are common at region crossing. 
So, at the same time we restart the animation, we reset the
camera parameters. This usually eliminates bogus camera motion
at region crossings. It also deals with the problem of slow loss of
camera position over time due to some cumulative error problem. 


## Road problems, or "potholes".
As pointed out above, regions are really islands, and a region crossing
means going off the edge and being teleported to the next region. 
When an avatar or vehicle goes off the edge of a region, and there's
nothing extending beyond the region boundary to support it, it falls
a short distance. Then the teleport starts, and when the object arrives
at the new sim, the physics engine tries to get it out of overlap with
the surface in the new sim. 

A small downward movement at a region crossing is so common that it's
a cliche in Second Life. If the movement downward is too far, the 
avatar or vehicle can fall clear through what appears to be a solid
surface. Thin bridges and floors often cause this failure. 

If the surface has two layers, such as a road on top of land, and
the avatar or vehicle sinks through the top layer during a region
crossing, the object can become trapped. The constraint engine in
the physics simulator is trying to keep the object above the ground
but below the road prim. There is no good solution to that problem,
and the object becomes trapped.

A milder form of trapping is a "trip", where, at a region crossing,
this problem results in a collision between the slightly sunken
avatar and a prim, resulting in unwanted motion in some direction.

This problem can be fixed by extending road prims a few meters off
the edge of the sim. This has been known since at least 2012.
Such a prim provides support during the transition.
The extension can be transparent, and it can be an additional 
prim tacked onto an existing road prim. Some roads in Second Life
already have such support. Some don't. (Circuit de Corse is quite good;
Kama City intersections are terrible. Fixing Kama City would be easy,
because all the intersections are identical.)

# Conclusion
Almost all the problems with region crossings in Second Life can
be fixed or worked around without major modifications.
Except making them instantaneous. 








