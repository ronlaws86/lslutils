//
//   pathbuildutils.lsl -- components of a path building system
//
//   Part of a system for doing pathfinding in Second Life
//
//   Animats
//   June, 2019
//
#ifndef PATHBUILDUTILSLSL                                   // include guard, like C/C++
#define PATHBUILDUTILSLSL
#include "npc/assert.lsl"                                   // assert
#include "npc/mazedefs.lsl"
//
//  Constants
//
integer CASTRAYRETRIES = 10;                                // retry up to 10 times
float CASTRAYRETRYDELAY = 0.200;                            // if a problem, retry slowly
float GROUNDCLEARANCE = 0.05;                               // avoid false ground collisions
float MAXAVOIDMOVE = 8.0;                                   // max distance to avoid obstacle
float PATHCHECKTOL = 0.02;                                  // allow 2cm collinearity error
#ifndef INFINITY                                            // should be an LSL builtin
#define INFINITY ((float)"inf")                             // is there a better way?
#endif // INFINITY
#ifndef NAN
#define NAN ((float)"nan")
#endif // 

//
//  Globals
//
integer gPathErrorStatus = 0;                               // last error
vector gPathErrorPos;                                       // world pos of last error

//
//  patherror - record error
//
patherror(integer status, vector pos)
{   if (gPathErrorStatus != 0) return;                      // not first error, ignore
    gPathErrorStatus = status;                              // what
    gPathErrorPos = pos;                                    // where
    DEBUGPRINT1("Path error " + (string)status + " at " + (string)pos); 
}


//
//  
//
//  distpointtoline -- point to line distance, infinite line
//
//  Formula from geomalgorithms.com
//
float distpointtoline(vector p, vector p0, vector p1)
{
     vector v = p1 - p0;                // the line
     vector w = p - p0;                 
     float c1 = w*v;
     float c2 = v*v;                    // length squared
     vector pb;
     if (c2 > 0.00001)                  // nonzero line length
     {  float b = c1 / c2;              // would divide by 0 for null line
        pb = p0 + b * v;                // closest point on line to p
     } else {
        pb = p0;                        // zero length line case
     }
     return (llVecMag(p - pb));             // return distance
}
//  
//  checkcollinear -- are points on list collinear?
//
integer checkcollinear(list pts)
{   integer length = llGetListLength(pts);
    if (length < 3) { return(TRUE); }    // collinear unless at least 3
    integer i;
    vector p0 = llList2Vector(pts,0);
    vector p1 = llList2Vector(pts,-1);  // last
    for (i=1; i<length-1; i++)          // points other than endpoints
    {   float dist = distpointtoline(llList2Vector(pts,i), p0, p1);    // dist from line between endpoints
        if (dist > PATHCHECKTOL) { return(FALSE); } // tolerance 1cm
    }
    return(TRUE);                       // collinear   
}
//
//  pathstraighten -- straighten a path if possible.
//
//  Works in 3D world, not maze cell space.
//
list pathstraighten(list pts, float width, float height, float probespacing, integer chartype)
{
    integer n = 0;
    //   Advance through route. On each iteration, either the route gets shorter, or n gets
    //   larger, so this should always terminate.
    while (n < llGetListLength(pts)-3)                          // advancing through route
    {   vector  p0 = llList2Vector(pts,n);                      // get next three points
        vector  p1 = llList2Vector(pts,n+1);                    // get next three points
        vector  p2 = llList2Vector(pts,n+2);                    // get next three points
        //  Try to take a short cut, bypassing p1
        if (obstaclecheckpath(p0, p2, width, height,probespacing, chartype))
        {   pts = llListReplaceList(pts,[],n+1,n+1);            // success, we can delete p2
        } else {                                                // can't delete, so advance
            n = n + 1;
        }
    }
    return(pts);                                                // shortened route
}

//
//  rotperpenonground  -- rotation to get line on ground perpendicular to vector
//
//  Used to construct the end lines of path segments.
//
rotation rotperpenonground(vector p0, vector p1)
{
    vector dir = llVecNorm(p1-p0);                          // direction for line
    rotation azimuthrot = llRotBetween(<1,0,0>, llVecNorm(<dir.x, dir.y, 0>));
    rotation elevrot = llRotBetween(llVecNorm(<dir.x, dir.y, 0>), dir); // elevation
    return(azimuthrot * elevrot);                           // apply in proper order
}

//
//  mazecellto3d  -- convert maze cell to 3D coords
//
//  mazecellsize is the size of a cell in the XY plane, not the 3D plane
//  mazepos is the position of cell (0,0);
//  mazerot is the rotation of the maze plane.
//
//  Used in multiple scripts.
//
vector mazecellto3d(integer x, integer y, float mazecellsize, vector mazepos, rotation mazerot)
{
    if (x == 0 && y == 0) { return(mazepos); }      // avoid divide by zero
    vector vflat = <x*mazecellsize,y*mazecellsize,0.0>;   // vector to cell in XY plane
    //  Calc X and Y in 2D space.
    vector azimuthvec = <1,0,0>*mazerot;           // rotation 
    azimuthvec = llVecNorm(<azimuthvec.x, azimuthvec.y,0.0>);   
    rotation azimuthrot = llRotBetween(<1,0,0>,azimuthvec);
    vector p = vflat*azimuthrot;             // vector in XY plane
    //  Vflatrot has correct X and Y. Now we need Z.
    vector planenormal = <0,0,1>*mazerot;          // normal to rotated plane. Plane is through origin here.
    //  Distance from point to plane is p*planenormal.  We want that to be zero.
    //  We want p.z such that p*planenormal = 0;
    //  want p.x*planenormal.x + p.y * planenormal.y + p.z * planenormal.z = 0
    p.z = - (p.x*planenormal.x + p.y * planenormal.y)/planenormal.z;    // planenormal.z cannot be zero unless tilted plane is vertical
    DEBUGPRINT1("mazecellto3d: x: " + (string)x + " y: " + (string)y + " p: " + (string)p + " p+mazepos: " + (string)(p+mazepos));
    return(p + mazepos);
}

//
//  castray -- llCastRay with retry
//
//  llCastRay can fail under overload. This is rare, but we have to retry.
//
list castray(vector p0, vector p1, list params)
{
    integer tries = CASTRAYRETRIES;                         // number of retries
    list castresult = [];
    while (tries-- > 0)
    {   
        castresult = llCastRay(p0, p1, params);             // try cast ray
        DEBUGPRINT1("Cast ray: p0: " + (string)p0 + "  p1: " + (string)p1 + " result: " + llDumpList2String(castresult,","));  
        if (llList2Integer(castresult,-1) >= 0)             // if good status
        {   return(castresult); }                           // non-error, return
        DEBUGPRINT1("Cast delayed: " + (string) llList2Integer(castresult,-1));  // ***TEMP***
        llSleep(CASTRAYRETRYDELAY);                         // error, wait and retry
    }
    //  Too many retries, give up
    return(castresult);                                     // return final failure
}
//
//  castbeam -- do multiple llCastRay operations to check if way is clear for movement
//
//  Returns distance, or INFINITY if no obstacle found, or negative of status code if error.
//  Ignores hits with walkable objects, so this is for horizontal scans only.
//
//  Minimum value of probecnt is 2.
//
float castbeam(vector p0, vector p1, float width, float height, float probespacing, integer wantnearest, list castparams)
{   float yoffset;                                          // cast ray offset, Y dir in coords of vector
    float zoffset;                                          // cast ray offset, Z dir in coords of vector
    float nearestdist = INFINITY;                           // closest hit
    ////DEBUGPRINT1("p0: " + (string)p0 + "  p1: " + (string)p1 + " probespacing: " + (string) probespacing);  // ***TEMP***
    integer probecount = (integer)((height-GROUNDCLEARANCE)/probespacing); // number of probes
    if (probecount < 1) { probecount = 1; }                 // minimum is one probe
    probespacing = (height-GROUNDCLEARANCE)/probecount;     // adjust to match height
    if (probespacing < 0.10) { return(-4); }                // Bad call
    vector dir = llVecNorm(p1-p0);                          // direction of raycast 
    vector endoffsetdir = <0,1,0>*rotperpenonground(p0,p1);    // offset for horizontal part of scan
    ////DEBUGPRINT1("End offset dir: " + (string)endoffsetdir);  // ***TEMP***
    //  Always do 3 scans across width - left edge, middle, right edge.
    for (yoffset = -width * 0.5; yoffset <= width * 0.5 + 0.001; yoffset += (width*0.5))
    {   for (zoffset = GROUNDCLEARANCE; zoffset <= height  + 0.001; zoffset += probespacing)
        {   ////DEBUGPRINT1("p0: " + (string)p0 + "  p1: " + (string)p1 + "  zoffset: " + (string)zoffset); // ***TEMP***
            vector yadjust = yoffset*endoffsetdir;          // offset for scan crosswise to path
            list castresult = castray(<p0.x, p0.y, p0.z+zoffset>+yadjust, <p1.x, p1.y, p1.z + zoffset>+yadjust, castparams);
            integer status = llList2Integer(castresult, -1);// status is last element in list
            if (status < 0)
            {   DEBUGPRINT1("Cast ray status: " + (string)status);
                return((integer)status);                    // fails       
            }
            if (status > 0) { 
                vector hitpt = llList2Vector(castresult, 1); // get point of hit
                key hitobj = llList2Key(castresult, 0);     // get object hit
                list details = llGetObjectDetails(hitobj, [OBJECT_PATHFINDING_TYPE]);
                integer pathfindingtype = llList2Integer(details,0);    // get pathfinding type
                if (pathfindingtype != OPT_WALKABLE)        // if it's not a walkable
                {   float dist = (hitpt-p0) * dir;          // distance to hit
                    if (dist < 0) { dist = 0; }             // can potentially be small and negative, from geometry. Treat as zero.
                    if (!wantnearest)                       // if don't need nearest
                    {   return(dist); }                     // just return first
                    if (dist < nearestdist)                 // save closest hit point
                    {   nearestdist = dist; }
                }
            }          
        }
    }
    return(nearestdist);   // no obstacles
}
//
//  obstaclecheckpath  -- is path obstacle-free?
//
//  Does both a ray check and a llGetStaticPath check.
//
//  NEEDS WORK to be usable from the maze solver on irregular terrain.
//
integer obstaclecheckpath(vector p0, vector p1, float width, float height, float probespacing, integer chartype)
{
    list path = llGetStaticPath(p0,p1,width*0.5, [CHARACTER_TYPE, CHARTYPE]);
    integer status = llList2Integer(path,-1);                   // last item is status
    path = llList2List(path,0,-2);                              // remove last item
    if (status != 0 || llGetListLength(path) > 2 && !checkcollinear(path))
    {   DEBUGPRINT1("Path static check failed for " + (string)p0 + " to " + (string)p1 + ": " + llDumpList2String(path,","));
        return(FALSE);
    }
    //  Don't test against land, because the static path check did that already.
    float disttohit = castbeam(p0, p1, width, height, probespacing, FALSE, [RC_REJECT_TYPES,RC_REJECT_LAND]);
    if (disttohit != INFINITY)
    {   DEBUGPRINT1("Obstacle check path from " + (string)p0 + " " + (string)p1 + " hit at " + (string)(p0 + llVecNorm(p1-p0)*disttohit));
        return(FALSE);
    }
    return(TRUE);                                               // success
}
//
//  obstaclecheckcelloccupied  -- is there an obstacle in this cell?
//
//  Checks a cell centered on p1. Assumes the cell centered on p0 is clear. Alignment of cell is p1-p2.
//
//  This works by doing one ray cast straight down, and two straight up. The downward cast must hit a
//  wallkable. The upward casts must hit nothing. This catches big objects sitting on the walkable
//  surface.
//
//  We don't have to check the trailing edge of the cell, because we are coming from a clear cell at p0,
//  so that was already cheked.
//
//  No static path check, but it has to hit a walkable.
//
//  p0 and p1 must be one width apart. 
//
//  
//
integer obstaclecheckcelloccupied(vector p0, vector p1, float width, float height, integer dobackcorners)
{
    float MAZEBELOWGNDTOL = 0.40;                           // cast downwards to just below ground
    vector dv = p1-p0;                                      // direction, unnormalized
    vector dvnorm = llVecNorm(dv);                          // 3D direction, normalized.
    float mazedepthmargin = 0.5*width*llFabs(dvnorm.z)+MAZEBELOWGNDTOL;   // allow for sloped area, cast deeper
    dv.z = 0;
    vector dir = llVecNorm(dv);                             // forward direction, XY plane
    p0 = p1 - dir*(width*1.5);                              // start casts from far side of previous cell
    vector crossdir = dir % <0,0,1>;                        // horizontal from ahead point
    DEBUGPRINT1("Cell edge check: dir = " + (string)dir + " crossdir: " + (string)crossdir + " p0: " + (string) p0 + " p1: " + (string)p1);
    vector pa = p1 + (crossdir*(width*0.5));                // one edge at ground level
    vector pb = p1 - (crossdir*(width*0.5));                // other edge at ground level
    vector pc = p1 + (dir*(width*0.5));                     // ahead at ground level
    vector pd = p1 - (dir*(width*0.5));                     // "behind" point 
    DEBUGPRINT1("Cell occupied check: " + (string)(p1+<0,0,height>) + " " + (string) (p1-<0,0,mazedepthmargin>)); // ***TEMP***
    list castresult = castray(p1+<0,0,height>, p1-<0,0,mazedepthmargin>,[]);    // probe center of cell, looking down
    if (!mazecasthitonlywalkable(castresult, FALSE)) { return(TRUE); }  // must hit walkable   
    //  Horizontal checks in forward direction to catch tall obstacles or thin ones.
    castresult = castray(p0+<0,0,height*0.5>,p1+dir*(width*0.5)+<0,0,height*0.5>,[]); // Horizontal cast at mid height, any non walkable hit is bad
    if (!mazecasthitonlywalkable(castresult, TRUE)) { return(TRUE); }  // if any non walkable hits, fail    
    castresult = castray(p0+<0,0,height*0.1>,p1+dir*(width*0.5)+<0,0,height*0.1>,[]); // Horizontal cast near ground level, any non walkable hit is bad
    if (!mazecasthitonlywalkable(castresult, TRUE)) { return(TRUE); }  // if any non walkable hits, fail    
    castresult = castray(p0+<0,0,height>,p1+dir*(width*0.5)+<0,0,height>,[]); // Horizontal cast at full height, any hit is bad
    if (!mazecasthitonlywalkable(castresult, TRUE)) { return(TRUE); }  // if any non walkable hits, fail    

    //  Crosswise horizontal check.
    castresult = castray(pa+<0,0,height*0.5>,pb+<0,0,height*0.5>,[]); // Horizontal cast, any hit is bad
    if (!mazecasthitonlywalkable(castresult, TRUE)) { return(TRUE); }  // if any non walkable hits, fail    
    //  Center of cell is clear and walkable. Now check upwards at front and side.
    //  The idea is to check at points that are on a circle of diameter "width"
    DEBUGPRINT1("Obstacle check if cell occupied. pa: " + (string)pa + " pb: " + (string)pb + " width: " + (string)width + " height: " + (string)height);     // ***TEMP***
    //  Downward ray casts only.  Must hit a walkable.   
    castresult = castray(pa+<0,0,height>,pa-<0,0,mazedepthmargin>,[]); // cast downwards, must hit walkable
    if (!mazecasthitonlywalkable(castresult, FALSE)) { return(TRUE); }// if any non-walkable hits, fail
    castresult = castray(pb+<0,0,height>,pb-<0,0,mazedepthmargin>,[]); // cast downwards, must hit walkable
    if (!mazecasthitonlywalkable(castresult, FALSE)) { return(TRUE); }    // if any non-walkable hits, fail
    castresult = castray(pc+<0,0,height>,pc-<0,0,mazedepthmargin>,[]); // cast downwards, must hit walkable
    if (!mazecasthitonlywalkable(castresult, FALSE)) { return(TRUE); }    // if any non-walkable hits, fail
    castresult = castray(pd+<0,0,height>,pc-<0,0,mazedepthmargin>,[]); // cast at steep angle, must hit walkable
    if (!mazecasthitonlywalkable(castresult, FALSE)) { return(TRUE); }    // if any non-walkable hits, fail
    if (!dobackcorners) 
    {   DEBUGPRINT1("Cell at " + (string)p1 + " empty.");           
        return(FALSE); 
    }
    //  Need to do all four corners of the square. Used when testing and not coming from a known good place.
    castresult = castray(pd+<0,0,height>,pd-<0,0,MAZEBELOWGNDTOL>,[]); // cast upwards, no land check
    if (!mazecasthitonlywalkable(castresult, TRUE)) { return(TRUE); }    // if any non-walkable hits, fail
    DEBUGPRINT1("Cell at " + (string)p1 + " empty.");           
    return(FALSE);                                               // success, no obstacle
}
//
//  mazecasthitonlywalkable  -- true if cast ray hit a walkable, only. Used for downward casts
//
integer mazecasthitonlywalkable(list castresult, integer nohitval)
{
    integer status = llList2Integer(castresult, -1);        // status is last element in list
    if (status < 0)
    {   DEBUGPRINT1("Cast ray error status: " + (string)status);
        return(FALSE);                                      // fails, unlikely       
    }
    if (status == 0) { return(nohitval); }                  // hit nothing, use no hit value
    if (status != 1) { return(FALSE); }                     // problem, fails
    vector hitpt = llList2Vector(castresult, 1);            // get point of hit
    key hitobj = llList2Key(castresult, 0);                 // get object hit
    if (hitobj == NULL_KEY) { return(TRUE); }               // null key is land, that's OK
    list details = llGetObjectDetails(hitobj, [OBJECT_PATHFINDING_TYPE]);
    integer pathfindingtype = llList2Integer(details,0);    // get pathfinding type
    if (pathfindingtype != OPT_WALKABLE)                    // if it's not a walkable
    {   DEBUGPRINT1("Hit non-walkable " + llList2String(llGetObjectDetails(hitobj,[OBJECT_NAME]),0) + " at " + (string)(hitpt));                // ***TEMP***
        return(FALSE);                                      // hit non-walkable, obstructed
    }
    return(TRUE);                                           // hit only a walkable - good.    
}
//
//  pathcalccellmovedist 
//
//  How far to move in dir to get an integral number of cells between points.
//  We need to move the point by a small distance in dir to achieve this.
//  Movement must always increase prevdist
//
//  Goal: |endpt - (pnt+dir*movedist)| mod cellsize == 0
//
//  with all the vectors in the XY plane only.
//
//  Derivation:
//
//    Number of cells needed, rounding up from what we have
//
//      unitcells = ceil(|pnt-endpt| / cellsize)
//
//    So we want this relationship:
//
//      |endpt - (pnt+dir*movedist)| = unitcells * cellsize  
//
//    Solve for movedist.
//
//      Let cdist = unitcells*cellsize
//      Let cdistsq = cdist^2
//      Let dv = endpt - pnt
//      Let dvsq = dv*dv
//
//    so
//
//      |dv - dir*movedist| = cdist 
//
//    or
//
//      |dv - dir*movedist|^2 = cdist^2
//
//    Expand length of vector
//      
//      (dv - dir*movedist)*(dv - dir*movedist) = cdistsq
//
//      dv*dv - 2*dir*movedist*dv + dir*dir*movedist*movedist = cdistsq
//
//      (dir*dir) * movedist^2 + movedist*(2*dir) + dv*dv - cdistsq = 0
//
//   Which is a quadratic.
//
//      a = dir*dir = 1
//      b = 2*dir*dv
//      c = dvsq - cdistsq
//
//      
//  This is just geometry.
//  It's really finding a point which is on an XY plane circle centered at endpt and an
//  integral number of widths from it, and also on the line from pnt along vector dist.
//
//
float pathcalccellmovedist(vector pnt, vector dir3d, vector endpt, float cellsize, float prevdist3d)
{
    if (endpt == ZERO_VECTOR) { return(prevdist3d+cellsize); }   // no endpt constraint, simple solution
    vector endptflat = <endpt.x, endpt.y, 0.0>;     // project endpoint into XY plane
    vector pntflat = <pnt.x,pnt.y,0.0>;             // project pnt into XY plane
    vector dirflat = llVecNorm(<dir3d.x, dir3d.y,0.0>);    // project direction into XY plane
    float scale2d = dirflat*dir3d;                  // scale 3D lengths in dir down to 2D
    float prevdistflat = prevdist3d * scale2d;      // XY plane length of prevdist
    vector p0 = pntflat+(dirflat*(prevdistflat+0.01));  // starting point, just past prevdist to force progress
    assert(llFabs(p0.z) < 0.001);                   // p0 is in XY plane
    float p0toendptflat = llVecMag(p0-endptflat);   // approx dist to center
    integer unitcells = llCeil(p0toendptflat/cellsize);     // number of cells desireed between endpoints
    float cdist = unitcells*cellsize;               // desired distance to endpt
    float cdistsq = cdist*cdist;                    // distance squared
     //  Wanted: |endptflat - (pntflat+dirflat*movedist)| = cdist 
    vector dv = endptflat - pntflat;                // start point to center  
    float dvsq = dv*dv;                             // distance squared
    float a = 1;                                    // quadratic solution
    float b = 2*(dv*dirflat);
    float c = dvsq - cdistsq;
    float numersq = b*b-4*a*c;                       // term under radical in quadratic equation
    if (numersq < 0.0) { return(NAN); }              // Error
    float numer = llSqrt(numersq);                   // must be nonnegative
    float movedistflat = (-b - numer) / (2*a);       // the smaller quadatic solution.
#ifdef OBSOLETE
    DEBUGPRINT1("path cell move calc.  llFabs(llVecMag((endptflat - (pntflat+dirflat*(-movedistflat))() : " 
        + (string) llFabs(llVecMag((endptflat - (pntflat+dirflat*(-movedistflat)))))
        + " unit cells: " + (string)unitcells + " cell size: " + (string)cellsize + " pntflat: " + (string)pntflat + " endpflat: "
        + (string)endptflat +  " p0: " + (string)p0 + " dirflat: " + (string)dirflat + " movedistflat: "  
        + (string)movedistflat);
#endif // OBSOLETE
    assert(llFabs(a*movedistflat*movedistflat + b*movedistflat + c) < 0.001);   // quadratic equation check
    movedistflat = -movedistflat;                   // ***NOT SURE ABOUT THIS***
    if (movedistflat < 0) { return(NAN); }
    assert(llFabs(llVecMag(endptflat - (pntflat + dirflat*movedistflat)) - unitcells*cellsize) < 0.01); // math check
    assert(movedistflat > prevdistflat);            // must increase dist  
    float movedist3d = movedistflat / scale2d;      // scale up for 3D
    return(movedist3d);                             // move this far along segment in 3D 
}
//
//
//  pathfindunobstructed -- find an unobstructed point near a path segment end.
//
//  Returns [pnt,ix], where ix is the point index previous, in the direction of scan, to the
//  scan, of the point found.
//
//
//
list pathfindunobstructed(list pts, integer ix, integer fwd, float width, float height)
{
    assert(fwd == 1 || fwd == -1);
    DEBUGPRINT1("Looking for unobstructed point on segment #" + (string)ix + " fwd " + (string)fwd); 
    if (ix < 0 || ix+fwd<0) { return([ZERO_VECTOR,-1]);} 
    integer length = llGetListLength(pts);
    vector p0 = llList2Vector(pts,ix);      // index of previous point
    vector p1 = llList2Vector(pts,ix + fwd);// index of next point
    vector dir = llVecNorm(p1-p0);          // move dir
    float distalongseg = 0.001;                  // just enough to get into segment
    // distance along segment starting at ix.
    while (TRUE)                                // until return
    {   
        p0 = llList2Vector(pts,ix);             // index of previous point
        p1 = llList2Vector(pts,ix + fwd);       // index of next point
        dir = llVecNorm(p1-p0);                 // move dir
        vector pos = p0 + llVecNorm(p1-p0) * distalongseg; // next point to try
        float vlen = llVecMag(p1-p0);           // length of vector
        if (distalongseg > vlen)                // if hit end of segment
        {   ix = ix + fwd;                      // advance one seg in desired dir
            if (ix + fwd >= length || ix + fwd < 0) // end of entire path without find
            {   DEBUGPRINT1("Fail: no clear point on segment #" + (string)ix + " at " + (string)pos + " fwd " + (string)fwd);  
                return([ZERO_VECTOR,-1]);       // hit end of path without find, fails
            }
            distalongseg = 0.001;               // just enough into new seg

        } else {                                // did not hit end of segment
            DEBUGPRINT1("Trying point on segment #" + (string)ix + " at " + (string)pos + " fwd " + (string)fwd);  
            if (!obstaclecheckcelloccupied(p0, pos, width, height, TRUE))
            {   DEBUGPRINT1("Found clear point on segment #" + (string)ix + " at " + (string)pos + " fwd " + (string)fwd); 
                return([pos,ix]);               // found an open spot
            }
            distalongseg += width;              // advance one width
        }
    }
    //  Unreachable
    return([ZERO_VECTOR,-1]);                   // no way
}
//
//  pathclean - remove very short segments from path. llGetStaticPath has a problem with this.
//
list pathclean(list path)
{   
    integer len = llGetListLength(path);                    // number of points on path
    if (len == 0)  { return([]); }                          // empty list
    vector prevpt = llList2Vector(path,0);                  // previous point
    list newpath = [];                                      // which is the first output point
    integer i;
    for (i=1; i<len; i++)                                   // for all points after first
    {   vector pt = llList2Vector(path,i);                  // get next pont
        float dist = llVecMag(pt - prevpt);                 // segment length
        if (dist > MINSEGMENTLENGTH)                        // if long enough to keep
        {   newpath += prevpt;
            prevpt = pt;
        }
    }
    newpath += llList2Vector(path,-1);                      // always include final point
    return(newpath);                                        // cleaned up path
}
//
//  pathcheckobstacles -- check a path for obstacles.
//
//  Output is a strided list of the form [pnt, unblocked, pnt, unblocked ...]
//
//  (Replaces pathcheckobstacles and pathendpointadjust.)
//
//  Input conditions - first and last point are unobstructed. That's all we know.
//
//  All points must be unobstructed. Obstructed points must be marked as 
//  ends of blocked segments. Blocked segments must be at least 2 widths long,
//  so the maze solver can run.
//
//
list pathcheckobstacles(list pts, float width, float height, integer verbose)
{   
    list pathPoints = [];                                   // output points
    integer len = llGetListLength(pts);
    if (len < 2) { return([]);}                             // empty list
    DEBUGPRINT1("path check for obstacles. Segments: " + (string)len); 
    vector p0 = llList2Vector(pts,0);                       // starting position
    vector p1 = llList2Vector(pts,1);                       // next position
    float distalongseg = 0.0;                               // starting position, one extra width
    integer currentix = 0;                                  // working on segment 0
    while (TRUE)                                            // until return
    {   //  Check segment for obstacles, going forward.
        float fulllength = llVecMag(p1-p0);                 // full segment length
        vector dir = llVecNorm(p1-p0);                      // direction of segment
        vector pos = p0 + dir*distalongseg;                 // current working position
        DEBUGPRINT1("Checking " + (string)pos + " to " + (string)p1 + " for obstacles.");
        float hitdist = castbeam(pos, p1, width, height, TESTSPACING, TRUE,
                    [RC_REJECT_TYPES,RC_REJECT_LAND]);
        if (hitdist < 0)
        {  
            patherror(MAZESTATUSCASTFAIL, pos);             // failure
            return([]);                                     // failure
        }    
        if (hitdist == INFINITY)                            // completely clear segment
        {
            pathPoints += [pos, TRUE];                      // completely empty segment
            currentix += 1;                                 // advance to next segment
            if (currentix >= len-1)                         // done
            {   pathPoints += [p1, TRUE];                   // finish off final segment
                return(pathPoints);                         // return strided list of path segments
            }
            p0 = llList2Vector(pts,currentix);              // starting position in new segment
            p1 = llList2Vector(pts,currentix+1);            // next position
            distalongseg = 0.0;                             // starting new segment
        } else {                                            // there is an obstruction        
            vector interpt0 = pos + dir*(hitdist-width);    // back away from obstacle.
            if (verbose) { llOwnerSay("Hit obstacle at segment #" + (string)currentix + " " + (string) interpt0); }
            if (distalongseg + hitdist-width < 0)           // too close to beginning of current segment to back up
            {                                               // must search in previous segments
                list pinfo =  pathfindunobstructed(pts, currentix-1, -1, width, height);
                interpt0 = llList2Vector(pinfo,0);          // open space point before obstacle, in a prevous segment
                integer newix = llList2Integer(pinfo,1);    // segment in which we found point
                DEBUGPRINT1("Pathcheckobstacles backing up from segment #" + (string)currentix + " to #" + (string) newix);
                if (newix < 0) { patherror(MAZESTATUSBADSTART, pos); return([]); }  // no open space found, fail
                vector p0work = llList2Vector(pts,newix);              // starting position in new segment
                 //  Need to discard some points in pathPts because we backed through them.
                //  ***CHECK THIS*** - compares on point position and might discard the whole list. Or it might discard a blocked area.
                while ((llGetListLength(pathPoints) > 0) && llVecMag(llList2Vector(pathPoints,-2)-p0work) > 0.001)         // while have path points left
                {   
                    DEBUGPRINT1("Dropping point " + (string)llList2Vector(pathPoints,-2) + " from pathPoints looking for " + (string)p0work);
                    pathPoints = llListReplaceList(pathPoints,[],llGetListLength(pathPoints)-2, llGetListLength(pathPoints)-1);
                }
                if (llGetListLength(pathPoints) == 0)                                       // if lost entire list
                {   patherror(MAZESTATUSBADBACKUP, p0work); return([]); }                       // fails
            }
            //  Search for the other side of the obstacle.                     
            DEBUGPRINT1("Looking for open space on far side of obstacle.");
            list obsendinfo = pathfindclearspace(pts, interpt0, currentix, width, height, verbose);    // find far side of obstacle
            if (llGetListLength(obsendinfo) < 2)
            {   if (verbose) { llOwnerSay("Cannot find open space after obstacle at " + (string)interpt0 + " on segment #" + (string)(currentix-1));}
                patherror(MAZESTATUSBADOBSTACLE, interpt0);     // cannot find open space after obstacle
                pathPoints += [p0, TRUE, interpt0, FALSE];
                return(pathPoints);                             // best effort result
            }
            //  Found point on far side, we have something for the maze solver.
            vector interpt1 = llList2Vector(obsendinfo,0);      // clear position on far side
            integer interp1ix = llList2Integer(obsendinfo,1);   // in this segment
            if (verbose) { llOwnerSay("Found open space at segment #" + (string) interp1ix + " " + (string)interpt1); }
            pathPoints += [p0, TRUE, interpt0, FALSE, interpt1, TRUE];
            if (llVecMag(interpt1 - llList2Vector(pts,len-1)) < 0.01)  // if at final destination
            {   return(pathPoints);  }                          // done, return strided list of path segments
            assert(interp1ix < len-1);                          // ix must never pass beginning of last segment
            //  Forward progress check to prevent infinite loop. Must either advance segment, or be further from start of current segment.
            assert(interp1ix > currentix || (llVecMag(llList2Vector(pts, currentix) - p0) < llVecMag(llList2Vector(pts, currentix) - interpt1)));
            currentix = interp1ix;                              // continue from point just found
            p0 = llList2Vector(pts,currentix);                  // starting position in new segment
            p1 = llList2Vector(pts,currentix+1);                // next position
            distalongseg = llVecMag(interpt1 - p0);             // how far along seg 
        }
    }
    return([]);                                                 // unreachable
}
//
//  pathfindclearspace -- find clear space after obstacle
//
//  Returns [pos, segmentid] or [] if fail.
//
//  This is very difficult, if not impossible, to do perfectly.
//  llCastRay will not tell us if the starting position is inside an obstacle. So there's some guessing involved.
//  If we guess wrong, the problem will be detected when the character follows the path.
//
list pathfindclearspace(list pts, vector startpos, integer obstacleix, float width, float height, integer verbose)
{
    //  Dumb version. Just try the same check the maze solver uses, advancing along the path, until we find open space.
    integer len = llGetListLength(pts);
    vector p0 = llList2Vector(pts,obstacleix);
    vector p1 = llList2Vector(pts,obstacleix+1);
    vector pos = startpos;                                          // start search here
    vector prevpos = pos;                                           // need current and previous points
    //  Starting position is one extra width from start to provide some separation between start and finish.
    float distalongseg = llVecMag(pos - p0) + width;                // starting position, one extra width
    float seglength = llVecMag(p1-p0);
    integer currentix = obstacleix;                                 // working on segment 0
    while (TRUE)
    {   //  Advance one width
        distalongseg = distalongseg + width;                        // advance half width
        prevpos = pos;
        if (distalongseg > seglength)                               // if reached end of segment
        {   if (currentix >= len-2)                                 // must be able to advance
            {   return([]);                                         // reached end with no find. Caller reports error
            }
            currentix += 1;                                         // start next segment
            distalongseg = 0.0;                                     // start at next seg point, although arguably should advance around corner
        }
        p0 = llList2Vector(pts,currentix);
        p1 = llList2Vector(pts,currentix+1);
        seglength = llVecMag(p1-p0);                                // current segment length
        vector dir = llVecNorm(p1-p0);
        pos = p0+dir*distalongseg;                                  // next point to try
        // Adjust pos to be an integral number of widths from startpos. Movement is forward.
        float adjdistalongseg = pathcalccellmovedist(p0, dir, startpos, width, distalongseg);
        vector checkvec = (p0 + dir * adjdistalongseg) - startpos;                           // checking only
        DEBUGPRINT1("Maze endpoint adjust. Dist along seg " + (string)distalongseg + " -> " + (string)adjdistalongseg + " 2D dist: " + 
            (string)llVecMag(<checkvec.x,checkvec.y,0.0>));
        if (adjdistalongseg >= 0 && adjdistalongseg <= seglength)   // if still on same segment
        {   assert(adjdistalongseg >= distalongseg);                // must progress forward
            distalongseg = adjdistalongseg;
            pos = p0 + dir * distalongseg;                           // should be an integral number of widths from startpos in 2D plane.
            //  Test the new point.  This test is not airtight because we are not testing from open space.
            //  May need further checks here.
            if (!obstaclecheckcelloccupied(prevpos, pos, width, height, TRUE))
            {   
                return([pos,currentix]);                                // success, found open space
            }
        }
    }
    return([]);                                                     // unreachable  
}
#endif // PATHBUILDUTILSLSL

