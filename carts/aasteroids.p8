pico-8 cartridge // http://www.pico-8.com
version 16
__lua__
-- aasteroids
-- by freds72

-- aaline by felice
local ramp={[0]=7,7,7,7,7,6,6,6,13,13,13,5,5,1,1,0}

-- pico-8 resets the palette
-- when you stop the app, so
-- just run one of these as
-- needed.
function grayvid()
	for i=0,15 do
		pal(i,i,0)
		pal(i,ramp[i],1)
		palt(i,false)
	end
end
function normvid()
	for i=0,15 do
		pal(i,i,0)
		pal(i,i,1)
		palt(i,false)
	end
end

-- shade the pixel
-- abs(dist) indicates how far
-- we are from the exact
-- line center
function shadepix_xy(x,y,dist)
	pset(x,y,abs(dist*(pget(x,y))))
end

-- algorithm credits: felice
-- based off: http://jamesarich.weebly.com/uploads/1/4/0/3/14035069/480xprojectreport.pdf
function aaline(x0,y0,x1,y1)
	local w,h=abs(x1-x0),abs(y1-y0)
	
	-- to calculate dist properly,
	-- do this, but we'll use an
	-- approximation below instead.
 -- local d=sqrt(w*w+h*h)
 
 if h>w then
 	-- order points on y
 	if y0>y1 then
 		x0,y0,x1,y1=x1,y1,x0,y0
 	end
 
 	local dx=x1-x0
 	
 	-- apply the bias to the 
 	-- line's endpoints:
 	y0+=0.5
 	y1+=0.5
 
 	--x0+=0.5 --nixed by -0.5 in loop
 	--x1+=0.5 --don't need x1 anymore

		-- account for diagonal thickness
		-- thanks to freds72 for neat trick from https://oroboro.com/fast-approximate-distance/
  -- 	local k=h/d
		local k=h/(h*0.9609+w*0.3984)
 	
 	for y=flr(y0)+0.5-y0,flr(y1)+0.5-y0 do	
 		local x=x0+dx*y/h
 		-- originally flr(x-0.5)+0.5
 		-- but now we don't x0+=0.5 so not needed
 		local px=flr(x)
 		pset(px,  y0+y,pget(px,  y0+y)*k*(x-px  ))
 		pset(px+1,y0+y,pget(px+1,y0+y)*k*(px-x+1))
 	end
 elseif w>0 then
 	-- order points on x
 	if x0>x1 then
 		x0,y0,x1,y1=x1,y1,x0,y0
 	end
 
 	local dy=y1-y0
 	
 	-- apply the bias to the 
 	-- line's endpoints:
 	x0+=0.5
 	x1+=0.5
 
 	--y0+=0.5 --nixed by -0.5 in loop
 	--y1+=0.5 --don't need y1 anymore
	
		-- account for diagonal thickness
		-- thanks to freds72 for neat trick from https://oroboro.com/fast-approximate-distance/
  -- local k=w/d
		local k=w/(w*0.9609+h*0.3984)
 	
 	for x=flr(x0)+0.5-x0,flr(x1)+0.5-x0 do	
 		local y=y0+dy*x/w
 		-- originally flr(y-0.5)+0.5
 		-- but now we don't y0+=0.5 so not needed
 		local py=flr(y)
 		pset(x0+x,py,  pget(x0+x,py  )*k*(y-py  ))
 		pset(x0+x,py+1,pget(x0+x,py+1)*k*(py-y+1))
 	end
	end
end

-- anti-aliased circfill
-- credits: https://en.wikipedia.org/wiki/midpoint_circle_algorithm
-- pixel shading is based on error ratio
function aacircfill(x0,y0,r)
	if(r==0) return
 local x,y,dx,dy=flr(r),0,1,1
 r*=2
 local err=dx-r

	local j=0
 while x>=y do
		local dist=1+err/r
		rectfill(x0-x+1,y0+y,x0+x-1,y0+y,0)
		rectfill(x0-x+1,y0-y,x0+x-1,y0-y,0)
		rectfill(x0-y,y0-x+1,x0+y,y0-x+1,0)
		rectfill(x0-y,y0+x-1,x0+y,y0+x-1,0)
	 shadepix_xy(x0+x,y0+y,dist)
  shadepix_xy(x0+y,y0+x,dist)
  shadepix_xy(x0-y,y0+x,dist)
  shadepix_xy(x0-x,y0+y,dist)
  shadepix_xy(x0-x,y0-y,dist)
  shadepix_xy(x0-y,y0-x,dist)
  shadepix_xy(x0+y,y0-x,dist)
  shadepix_xy(x0+x,y0-y,dist)
 
	 if err<=0 then
   y+=1
   err+=dy
   dy+=2
		end  
	 if err>0 then
   x-=1
   dx+=2
   err+=dx-r
		end
	end
end

-- game globals
local time_t,time_dt=0,1
local cur_screen
local start_screen={}
local game_screen={
	starting=false
}

-- futures
local before_update,after_draw={},{}
function futures_update(futures)
	futures=futures or before_update
	for _,f in pairs(futures) do
		if not coresume(f) then
			del(futures,f)
		end
	end
end
function futures_add(fn,futures)
	return add(futures or before_update,cocreate(fn))
end
function wait_async(t,fn)
	local i=1
	while i<=t do
		if fn then
			if not fn(i) then
				return
			end
		end
		i+=time_dt
		yield()
	end
end

local cam_x,cam_y=0,0
local shkx,shky=0,0
function cam_shake(u,v,pow)
	shkx=min(4,shkx+pow*u)
	shky=min(4,shky+pow*v)
end
function cam_update()
	shkx*=-0.7-rnd(0.2)
	shky*=-0.7-rnd(0.2)
	if abs(shkx)<0.5 and abs(shky)<0.5 then
		shkx,shky=0,0
	end
	camera(shkx,shky)
end

function filter(array,fn)
	for _,a in pairs(array) do
		if not a[fn](a) then
			del(array,a)
		end
	end
end
function forall(array,fn)
	for _,a in pairs(array) do
		a[fn](a)
	end
end

function lerp(a,b,t)
	return a*(1-t)+b*t
end

-- asteroid font credits:
-- https://trmm.net/asteroids_font
-- "draw" command
local font_up={}
local fonts={
	['0'] = { {0,0}, {8,0}, {8,12}, {0,12}, {0,0}, {8,12}},
	['1'] = { {4,0}, {4,12}, {3,10}},
	['2'] = { {0,12}, {8,12}, {8,7}, {0,5}, {0,0}, {8,0}},
	['3'] = { {0,12}, {8,12}, {8,0}, {0,0}, font_up, {0,6}, {8,6}},
	['4'] = { {0,12}, {0,6}, {8,6}, font_up, {8,12}, {8,0}},
	['5'] = { {0,0}, {8,0}, {8,6}, {0,7}, {0,12}, {8,12}},
	['6'] = { {0,12}, {0,0}, {8,0}, {8,5}, {0,7}},
	['7'] = { {0,12}, {8,12}, {8,6}, {4,0}},
	['8'] = { {0,0}, {8,0}, {8,12}, {0,12}, {0,0}, font_up, {0,6}, {8,6}, },
	['9'] = { {8,0}, {8,12}, {0,12}, {0,7}, {8,5}},
	[' '] = { },
	['.'] = { {3,0}, {4,0}},
	[','] = { {2,0}, {4,2}},
	['-'] = { {2,6}, {6,6}},
	['+'] = { {1,6}, {7,6}, font_up, {4,9}, {4,3}},
	['!'] = { {4,0}, {3,2}, {5,2}, {4,0}, font_up, {4,4}, {4,12}},
	['#'] = { {0,4}, {8,4}, {6,2}, {6,10}, {8,8}, {0,8}, {2,10}, {2,2} },
	['^'] = { {2,6}, {4,12}, {6,6}},
	['='] = { {1,4}, {7,4}, font_up, {1,8}, {7,8}},
	['*'] = { {0,0}, {4,12}, {8,0}, {0,8}, {8,8}, {0,0}},
	['_'] = { {0,0}, {8,0}},
	['/'] = { {0,0}, {8,12}},
	['\\'] = { {0,12}, {8,0}},
	['@'] = { {8,4}, {4,0}, {0,4}, {0,8}, {4,12}, {8,8}, {4,4}, {3,6} },
	['$'] = { {6,2}, {2,6}, {6,10}, font_up, {4,12}, {4,0}},
	['&'] = { {8,0}, {4,12}, {8,8}, {0,4}, {4,0}, {8,4}},
	['['] = { {6,0}, {2,0}, {2,12}, {6,12}},
	[']'] = { {2,0}, {6,0}, {6,12}, {2,12}},
	['('] = { {6,0}, {2,4}, {2,8}, {6,12}},
	[')'] = { {2,0}, {6,4}, {6,8}, {2,12}},
	['{'] = { {6,0}, {4,2}, {4,10}, {6,12}, font_up, {2,6}, {4,6}},
	['}'] = { {4,0}, {6,2}, {6,10}, {4,12}, font_up, {6,6}, {8,6}},
	['%'] = { {0,0}, {8,12}, font_up, {2,10}, {2,8}, font_up, {6,4}, {6,2} },
	['<'] = { {6,0}, {2,6}, {6,12}},
	['>'] = { {2,0}, {6,6}, {2,12}},
	['|'] = { {4,0}, {4,5}, font_up, {4,6}, {4,12}},
	[':'] = { {4,9}, {4,7}, font_up, {4,5}, {4,3}},
	[';'] = { {4,9}, {4,7}, font_up, {4,5}, {1,2}},
	['"'] = { {2,10}, {2,6}, font_up, {6,10}, {6,6}},
	['\''] = { {2,6}, {6,10}},
	['`'] = { {2,10}, {6,6}},
	['~'] = { {0,4}, {2,8}, {6,4}, {8,8}},
	['?'] = { {0,8}, {4,12}, {8,8}, {4,4}, font_up, {4,1}, {4,0}},
	['a'] = { {0,0}, {0,8}, {4,12}, {8,8}, {8,0}, font_up, {0,4}, {8,4} },
	['b'] = { {0,0}, {0,12}, {4,12}, {8,10}, {4,6}, {8,2}, {4,0}, {0,0} },
	['c'] = { {8,0}, {0,0}, {0,12}, {8,12}},
	['d'] = { {0,0}, {0,12}, {4,12}, {8,8}, {8,4}, {4,0}, {0,0}},
	['e'] = { {8,0}, {0,0}, {0,12}, {8,12}, font_up, {0,6}, {6,6}},
	['f'] = { {0,0}, {0,12}, {8,12}, font_up, {0,6}, {6,6}},
	['g'] = { {6,6}, {8,4}, {8,0}, {0,0}, {0,12}, {8,12}},
	['h'] = { {0,0}, {0,12}, font_up, {0,6}, {8,6}, font_up, {8,12}, {8,0} },
	['i'] = { {0,0}, {8,0}, font_up, {4,0}, {4,12}, font_up, {0,12}, {8,12} },
	['j'] = { {0,4}, {4,0}, {8,0}, {8,12}},
	['k'] = { {0,0}, {0,12}, font_up, {8,12}, {0,6}, {6,0}},
	['l'] = { {8,0}, {0,0}, {0,12}},
	['m'] = { {0,0}, {0,12}, {4,8}, {8,12}, {8,0}},
	['n'] = { {0,0}, {0,12}, {8,0}, {8,12}},
	['o'] = { {0,0}, {0,12}, {8,12}, {8,0}, {0,0}},
	['p'] = { {0,0}, {0,12}, {8,12}, {8,6}, {0,5}},
	['q'] = { {0,0}, {0,12}, {8,12}, {8,4}, {0,0}, font_up, {4,4}, {8,0} },
	['r'] = { {0,0}, {0,12}, {8,12}, {8,6}, {0,5}, font_up, {4,5}, {8,0} },
	['s'] = { {0,2}, {2,0}, {8,0}, {8,5}, {0,7}, {0,12}, {6,12}, {8,10} },
	['t'] = { {0,12}, {8,12}, font_up, {4,12}, {4,0}},
	['u'] = { {0,12}, {0,2}, {4,0}, {8,2}, {8,12}},
	['v'] = { {0,12}, {4,0}, {8,12}},
	['w'] = { {0,12}, {2,0}, {4,4}, {6,0}, {8,12}},
	['x'] = { {0,0}, {8,12}, font_up, {0,12}, {8,0}},
	['y'] = { {0,12}, {4,6}, {8,12}, font_up, {4,6}, {4,0}},
	['z'] = { {0,12}, {8,12}, {0,0}, {8,0}, font_up, {2,6}, {6,6}},
}
local font_scale=6
function draw_char(c,x,y,scale)
	scale=scale or font_scale
	local font=fonts[c]
	if(not font) assert("unsupported char:"..c)
	local x0,y0
	local moveto=true
	for i=1,#font do
		local seg=font[i]
		if seg==font_up then
			moveto=true
			goto continue
		end
		if moveto then
			x0,y0=seg[1],12-seg[2]
		else
			local x1,y1=seg[1],12-seg[2]
			aaline(
				x+font_scale*x0/12,
				y+font_scale*y0/12,
				x+font_scale*x1/12,
				y+font_scale*y1/12)
			x0,y0=x1,y1
		end
		::continue::
		moveto=false
	end
end
function draw_text(s,x,y,scale)			
	for i=1,#s do
		draw_char(sub(s,i,i),x,y,scale)
		x+=scale+1
	end
end

local pixel_part=0
local flash_part=1
local parts={}
function make_part(x,y,u,v,f,typ)
	local ttl,draw,r,dr
	if typ==flash_part then
		draw=draw_circ_part
		ttl=24
		r=4
		dr=-0.5
	else
		ttl=24+rnd(4)-8
		draw=draw_part
	end
	return add(parts,{
		x=x,
		y=y,
		u=u,
		v=v,
		f=f,
		r=r,
		dr=dr,
		inertia=0.98,
		t=time_t+ttl,
		ttl=ttl,
		draw=draw,
		update=update_part
	})
end
function make_blt(x,y,u,v)
	local ttl=60+rnd(12)
	sfx(4)
	return add(parts,{
		x=x,
		y=y,
		u=u,
		v=v,
		f=1.2,
		inertia=1,
		t=time_t+ttl,
		ttl=ttl,
		draw=draw_blt,
		update=update_part,
		collide=collide_blt
	})	
end
function make_blast(x,y)
	local ttl=12
	sfx(1)
	add(parts,{
		x=x,
		y=y,
		u=0,
		v=0,
		f=0,
		r=12,
		dr=-1,
		inertia=1,
		t=time_t+ttl,
		ttl=ttl,
		draw=draw_circ_part,
		update=update_part
	})
	for i=0,8 do
		local angle=rnd()
		local u,v=cos(angle),sin(angle)
		make_part(x+8*u,y+8*v,u,v,rnd())		
	end
	cam_shake(rnd(),rnd(),5)
end

function update_part(self)
	if(self.t<time_t) return false
	self.x+=self.f*self.u
	self.y+=self.f*self.v
	self.f*=self.inertia
	
 self.x%=128
	self.y%=128

	if self.r then
		self.r+=self.dr
	end
	--	custom update function?
	if self.collide then
		return self:collide()
	end
	return true
	--return self.collide and  or true
end

function draw_circ_part(self)
	aacircfill(self.x,self.y,self.r)
end

function draw_part(self)
 pset(self.x,self.y,0)
 local d=1-0.75*self.f
 shadepix_xy(self.x+1,self.y,d)
 shadepix_xy(self.x,self.y+1,d)
 shadepix_xy(self.x-1,self.y,d)
 shadepix_xy(self.x,self.y-1,d)
end

function draw_blt(self)
	local x,y=self.x,self.y
	pset(x,y,0)
	local dx,dy=x-flr(x),y-flr(y)
	-- kind of unit circle dithering
	shadepix_xy(x+1,y,dx)
	shadepix_xy(x-1,y,1-dx)
	shadepix_xy(x,y-1,dx)
	shadepix_xy(x,y+1,1-dx)
end

local actors={}
local plyr
local npc_count=0
function make_plyr(x,y)
	return add(actors,{
		score=0,
		combo_mult=0,
		combo_t=0,
		safe_t=0,
		live=3,
		r=4,
		x=x,
		y=y,
		a=0.25,
		da=0,
		u=0,
		v=1,		
		f=0,
		acc=0.5,
		emit_t=0,
		fire_t=0,
		update=update_plyr,
		draw=draw_plyr
	})
end

function collide_blt(self)
	for _,a in pairs(actors) do
		-- rock?
		if a!=plyr then
			local dx,dy=a.x-self.x,a.y-self.y
			if dx*dx+dy*dy<a.r*a.r then
				a.hp-=1
				if a.hp<=0 then
					plyr.score+=1
					plyr.combo_t=time_t+30

					a:die()
				else
					sfx(5)
					make_part(self.x,self.y,0,0,0,flash_part)
				end
				return false
			end
		end
	end
	return true
end

function make_rock(x,y,u,v,radius,n,hp)
	local angle,da=0,1/n
	local segments={}
	for i=1,n do
		local r=lerp(radius*0.8,radius*1.2,rnd())
		local y,x=r*cos(angle),-r*sin(angle)
		add(segments,{x=x,y=y})
		angle+=da
	end
		
	npc_count+=1
	add(actors,{
		hp=hp or 3,
		x=x,
		y=y,
		acc=0.25+0.25*rnd(),
		u=-u,
		v=v,
		a=rnd(),
		da=rnd()/64,
		r=radius, -- keep initial radius
		segments=segments,
		draw=draw_rock,
		update=update_rock,
		die=die_rock
	})
end

function rotate(x,y,c,s)
	return x*c-y*s,x*s+y*c
end
function draw_rock(self)	
	local u,v=cos(self.a),-sin(self.a)
	local r=self.segments[1]
	local rx,ry=rotate(r.x,r.y,u,v)
	local x0,y0,x1,y1=self.x+rx,self.y+ry
	local x2,y2=x0,y0
	for i=1,#self.segments do
		r=self.segments[i%#self.segments+1]
		rx,ry=rotate(r.x,r.y,u,v)
		x1,y1=self.x+rx,self.y+ry
		aaline(x0,y0,x1,y1)
		x0,y0=x1,y1
	end
end
function update_rock(self)
	self.a+=self.da
	self.x+=self.acc*self.u
	self.y+=self.acc*self.v
	
	self.x%=128
	self.y%=128
	return true
end

function die_rock(self)
	make_blast(self.x,self.y)
	
	npc_count-=1
	del(actors,self)

	-- spawn mini rocks
	local r=self.r/2
	if r>2 then
		local angle,da=rnd(),1/3
		for i=1,3 do
			local u,v=cos(angle),-sin(angle)
			make_rock(self.x+r*u,self.y-r*v,u,v,r,6,2)
			angle+=da
		end
	end
end

function control_plyr(self)
	if(btn(0)) self.da=-0.01
	if(btn(1)) self.da=0.01
	local thrust=false
	if(btn(4)) self.f=self.acc thrust=true
	local fire=false
	if(btn(5)) fire=true
	
	if fire and self.fire_t<time_t then
		self.fire_t=time_t+8
		make_blt(self.x,self.y,self.u,self.v)
	end
	
	if thrust and self.emit_t<time_t then
		sfx(2)
		self.emit_t=time_t+rnd(3)
		local emit_v=0.5+rnd()
		make_part(self.x-0.5*self.u,self.y-0.5*self.v,-self.u,-self.v,emit_v)
		make_part(self.x-4*self.u,self.y-4*self.v,-self.u,-self.v,0,flash_part)
	end
end

function update_plyr(self)
	self.a+=self.da	
	self.da*=0.90
	
	self.u=cos(self.a)
	self.v=-sin(self.a)
	
	self.x+=self.f*self.u
	self.y+=self.f*self.v

	self.x%=128
	self.y%=128
	
	self.f*=0.96
	
	return true
end

function draw_plyr(self)
	-- safe mode
	if(self.safe_t>time_t and time_t%2==0) return

	local a,r=self.a,self.r
	local x0,y0=self.x+r*cos(a),self.y-r*sin(a)
	a+=1/3
	local x1,y1=self.x+r*cos(a),self.y-r*sin(a)
	a+=1/3
	local x2,y2=self.x+r*cos(a),self.y-r*sin(a)
	
	aaline(x0,y0,x1,y1)			
	aaline(x0,y0,x2,y2)
 	aaline(x1,y1,x2,y2)
end

function resolve_collisions()
	if(plyr.safe_t>time_t) return

	local r=plyr.r
	-- crude distance check
	-- will do per-plane collision someday...
	for _,a in pairs(actors) do
		if a!=plyr then
			local dx,dy=a.x-plyr.x,a.y-plyr.y
			local d=a.r+r
			if dx*dx+dy*dy<d*d then
				make_blast(plyr.x,plyr.y)
				plyr.live-=1
				if plyr.live==0 then
					del(actors,plyr)
					plyr=nil
					futures_add(function()
						wait_async(60)
						cur_screen=start_screen
					end)
				else
					plyr.x,plyr.y,plyr.a,plyr.da=64,64,0.25,0
					plyr.u,plyr.v=0,1
					plyr.safe_t=time_t+45
				end
				return
			end
		end
	end
end

-- "crt" display effects
function crt_cls()
	-- scanline effect	
	local mem=0x6000
	for i=0,127 do
		local c=15-band(i,1)
		memset(mem,bor(shl(c,4),c),64)
		mem+=64
	end
end
function crt_glitch()
	-- cheap crt effect
	if rnd()>0.5 then
		-- avoid memcpy overflow
		local i=flr(rnd(126))
		local src,dst=0x6000+i*64,0x6000+i*64+2+flr(rnd(2))
		memcpy(dst,src,64)
	end
end

-- wait loop
function start_screen:update()
	if btnp(4) or btnp(5) then
		sfx(0)
		actors={}
		npc_count=0
		plyr=make_plyr(64,64)
		cur_screen=game_screen
	end
end
function start_screen:draw()
	if time_t%4<2 then	
		draw_text("press start",28,110,6)
	end
end

-- play loop
function game_screen:update()
	if(not plyr) return
	control_plyr(plyr)
	resolve_collisions()
end
function game_screen:draw()
	if(not plyr) return
	local x=8
	for i=1,plyr.live do
		draw_plyr({
			safe_t=0,
			r=4,
			x=x,
			y=18,
			a=0.75,
			u=0,v=-1})
		x+=8
	end
end

local spawning_npc=false
function _update60()
	time_t+=1
	time_dt+=1
	futures_update(before_update)
	if npc_count==0 and spawning_npc==false then
		spawning_npc=true
		futures_add(function()
			wait_async(60)
			sfx(3)
			local angle=rnd()
			for i=1,5 do
				local u,v=cos(angle),-sin(angle)
				make_rock(64+60*u,64-60*v,-u,-v,8,8)
				angle+=1/5
			end
			spawning_npc=false
		end)
	end
	
	cur_screen:update()
	
	filter(actors,"update")
	filter(parts,"update")	
		
	cam_update()
end

local stars={}
function _draw()
	crt_cls()
		
	for _,s in pairs(stars) do
		pset(s.x,s.y,15*s.c)
	end
	
	forall(actors,"draw")
	forall(parts,"draw")

	cur_screen:draw()
	
	-- score
	local score=tostr(plyr and plyr.score or 0)
	-- padding
	for i=1,4-#score do
		score="0"..score
	end
	draw_text(score,2,4,6)
	
	futures_update(after_draw)

	crt_glitch()
	time_dt=0
end

function _init()
	grayvid()
	
	for i=1,32 do
		add(stars,
			{x=rnd(127),
				y=rnd(127),
				c=rnd()})
	end

	cur_screen=start_screen
end

__gfx__
aaaaaaaaaaaa9999999444444444444444444444444444444444444455dddddddddddddddddddddddddddddddddddd5555555555ddddddddddaaaaaaaaaaaaaa
aaaaaaa9999999999999999999999999488888888888888888884444222555111111111111111111111111111555555555555555555555544aaaaaaaaaaaaaaa
aaaaaaa99999999999999999999999994888888888888888888844442225551111111111111111111111111111555555555555555555555baaaaaaaaaaaaaaaa
99999999444444444444444488888888888888888888888888888888444444444444444444444444444444444444444444444444444444444444444999999999
88888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888
88888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888
88888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888
88888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888
88888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888
88888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888
88888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888
88888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888
88888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888
88888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888
8888888888888888888888848888888848888884e448844444448844444888444488888844e488884488444488888884e448efff8f8888888888888888888888
888888888888888888888877488888877e888877777f87777777e477777e8e777774888777777488778877777748887777784f87478888888888888888888888
888888888888888888888477788888877788847f888488447f48847488888e74847788f7f884778877887784e7748f7488488f8f7f8888888888888888888888
888888888888888888888777788888e747488474888888887f88847488888e7888f748778888e74877887788847f877488888888888888888888888888888888
8888888888888888888847f47e888877877888777e4888887f88847ffff88e744477847f888847f87788778888778e7774888888888888888888888888888888
88888888888888888888e7487788847487788847777f88887f88847777788e777774887e888847f8778877888877884777748888888888888888888888888888
88888888888888888888777777488777777e8888847788887f88847488888e74f7e88877888847e8778877888877888884778888888888888888888888888888
888888888888888888847feee7f8877eee778888887788887f88847488888e748774887748887748778877888774888888778888888888888888888888888888
8888888888888888888778888778e74888f7447ff77788887f88847777778e748877884777f77e887788777777e8877ff7748888888888888888888888888888
888888888888888888877888847477888847f47777e888847e88847777774e748847f884f77748887788777fe4888e7777488888888888888888888888888888
88888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888
88888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888
88888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888
88888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888
88888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888
88888888888888888888888888888888888888888888888888888888888888888888888888488888888888888888888888888888888888888888888888888888
8888888888888888888888888888888888888888888888888888888888888888888888888d188888888888888888888888888888888888888888888888888888
88888888888888888888888888888888888888888888888888888888888888888888888461188888888888444888888888844888888888888888888888888888
8888888888888888888888888888888888888888888888888888888888888888888888f61118888888888d566de446445d46d548888888888888888888888888
8888888888888888888888888888888888888888888888888888888888888888888846d1111888888884ddd6666166d45d6d66d6488888888888888888888888
888888888888888888888888888888888888888888888888888888888844888888e66d1111148888884500111666005d5555d566648888888888888888888888
6666666666600100005500050000000000000010001111151555511111016111d666511111100000005100001d1d6d5056d6556ddd0000101110506666666666
6666666666600001005651d50000000040000001101101111151d51111000dd6666551111111000000500000005150051650505d050001011111116666666666
6666666666600001111555500006d1005900000000110011111115551100006d6655111110110000005100110050000505005105510001011111116666666666
66666666666000001110550000550d500490010101110001111515555510000651111111011100000001001110500001515005010111111d1111116666666666
666666666660011001100100001000d5059950011110000015115d66665000051111111011110000000511000000000015000515111111d11111116666666666
666666666661100000000100000001dd11699501111000000111d666777d00005111110111110000000015105100155555511110011111111111116666666666
666666666665515000000000000055550056f9011110000000156677777600001111101111110000010000550000155505115011111111111111116666666666
666666666665d5d1000000000000550010167f9111000010001d67777777d0011110111111110000050000051050555101010001111111111111116666666666
66666666666d115d10000000000000005501677411001000dd1d6777777760001110111111111000000000001111115051111010011111001111116666666666
66666666666d511510110000000000050500d67650000006dd0167777777d0001111111111110000000000100151151015011001011510001111116666666666
666666666665d5111155100000000000050010776100016d60005777777600001511111111110000000016560011115111011001111100000111116666666666
666666666665d55115100100100000001501111776155d5665000d777761000011111111111100000000d6665111111111111111110100000111116666666666
6666666666655d15515550000501100500111111666ddd6d66000006650000000111111111110000000006666511111510011011111000000111116666666666
66666666666155d1111d5101150000445001111556dd6656d6d000000000000001111101111d0000000010dd6611111110010011111000000011116666666666
666666666661155d5551dd5550000155011110106556d66dd66d0000000001000015111111110000000010005d11111111010010111000110011116666666666
666666666661111155ddd1115555500011115515666666dd561106d610000111101101111111d000000050105d11111111000551111001110001116666666666
6666666666611111155555511111101011111105666155d1615066d111000115500511111115dd50000015500511101111005d6d011010110001106666666666
6666666666611111155555111111111111d000d66666d61d11166d111111111015001111111001d000000100115111111015005d101110010001106666666666
66666666666111151115555111110111ddd5d66d56666651056611111111111111001111111000100000001510100111111100dd511111000100106666666666
666666666661111111515555111110d6dd666d655666615066611111111111110550011111100000000000055011111011101000511011100110116666666666
6666666666611111111115555111010066d566600666150666111511111111111110001111100000000000010001011101001005511101110111106666666666
66666666666101115111551155d5111006dddd6666515155611111111111111111500011111000001000001100010001010111011111111100d1106666666666
666666666661011151111115d6666510055d65165510561511111111111111111111000111510100000000110001111100000155000111110001006666666666
66666666666100011111155d677777d10060651500d16d111111111111111111111100011150550000000000110000dd10000011000001110000006666666666
6666666666611011111115d6777777600061110566d55111111111111111011111111000115011000000001111001155666dd111110000000001106666666666
666666666661000011d111677777777100510d6666101111111111111111101111111100015000000100000111100166666666d1111100010011006666666666
6666666666601010005011d7777777750056666511111111110111111111111111511110015000000110000100005dd666666666d51111100000006666666666
666666666665000000500057777777700066611111111111101011111151111115511110005000000110000000115d666666666666dd1d6d1110006666666666
6666666666601001116000067777776006d11551111111101111011111111115555011110050000000110000111d5d666666666666666d666d11006666666666
66666666666101010060011157777600111111111111111100111011111115555550011100110000011100001166666d0001d666666665666661116666666666
66666666666d1000166d000551111000015111111111111110111111111155555500011110050000001100001dd666610151556666666d566666d16666666666
666666666666dd156616500011000010015115111111111111100101115555550000001111051000001100015d66666d011000d66666666666666d6666666666
6666666666676d6666d11155110000011115515511111111111111115555550010500011110000000010110555ddd66650d11566666666666d6666d666666666
6666666666666666d11115515555101105115511111111111151115555510000001510011110510000101111550546666dd55666666666666666666d66666666
66666666666666511555551555155510051111111111111111111555005510001515510011105110001111110510d66666666666666666666666665666666666
66666666666d11551515511015555550001551111111111111155555510515000111111000110510001110500055d66dd6666666666666666666661566666666
66666666dd11515555500155555515515001551111111111115551050000155000551151015111110000005001051ddd0001d66666666666666666d566666666
6666666615115515100155555555515105000111111101115555115110015011001511150115101100010055151d1dd000000d66d555d666665d666d66666666
6666666666d5151515555151555510551151005115111155555555555500500010051151101001d00000001100155dd000000155000005dd665d666666666666
66666666666dddd5115511111151111551155511111115555d10155055040000000111111101110010000051000050051000011000000005d66666ddddd66666
66666666666d6d6666dd51111555115151111551111555d550100d550500000000001111110115101000005550000511d6d000000000000005666d5555566666
666666666666dd667776666dd51551111111111d11110000100011d115110001000001111150155000000015510000510500100000000000005dd00111566666
6666666666666ddd67776676dd15d51151511111551110000001551d1155111100000011111100010000001155510011100001100000000000051000001d6666
66666666666666ddd66777776d111111d511115515d1110000511511dd1151111000501111150001000000110055551000000555000000000001100111006666
66666666666766ddd667777776d1110101115511111d1111000515511555110010001051515001001500001110115555500005551000500000001165d1006666
666666666667666d6d677777776d1111000110005d515111100011111150500011100111510000010000001110155100050000566d55666d1000051151006666
6666666666676d666dd677777776d11111111000001115d111000011111155111110051d0000000100001011001550000000055dd666dddd5500000000056666
66666666666766d66dd677777777dd15111110000000011d5111000111111d001111010001001d5110001011011d100000000555dd6611d55500000010056666
66666666666776d66d6d667777776d51551110000000000115111100511111551115000000005500dd000010111550010000001000155055d015100000156666
666666666667776d66ddd667777776d551111000100000000055511001111155d551100000001555d1d000001100101d100000000000150000d66d6d55066666
66666666666d7666d66dd6777777776d11111011010000000000551110055111d00000000000000055dd00000500101dd155000000000000010000dd00166666
666666666665d66dd66ddd667777777dd55110111110000000000010510011510000005500000001110500001100101051550000000000000000000510666666
666666666665dd76dd766d6677777776d5d511111111100000000000d551000000000146d00000150155001011000d1051051511000000051000000010666666
666666666665dd666d666dd5666d67776d5511111111111001000000000000000000004ff5000010511000011000011100005555515000151150000055666666
666666666665dd666dd66d1500dd66677dd1d11111111010000000000000000000000004f4000001511000010110005110101010110000000000001055666666
6666666666655dd66ddd615d555d6d6776d55111111111100000000000000000000000004f50000011000011101510d505110000011000000000100105666666
66666666666ddd6d6ddd510d5001566677dd55111111111110010100000000000000000004f10000000111100010011d05511100000000100000110112666666
66666666666d5ddd66dd000100011d56677dd51111111111110100000000000000000000005f0000000555d511111111d5555110110100001000000051666666
666666666666d5dd76d50100000051106676d111111dd1111111000000000000100511000005d000501dd56ddd51511d155d5001510010000010501551666666
666666666666dddd67650500000010155d77dd111155d61111111000000000001d66dd000101550001115d6ddddd15ddd1155100015111000000100005666666
66666666666dddd666d655110015011554676d11150dd05d11111000000000056d6d5610000006000111dd6666dd1ddd51115001115101110000110555666666
66666666666dddd6d76dd55d55111115d6f776d111100d0d1111110100000000116d6d10000100d1115dd666666ddd55d1101111155500000501011056666666
66666666666dddddd66d6d5111511155567666d111511151111111001100001005000d110005610f115dd66d66666dd5510000111155510105051111d6666666
66666666666dddd6d66d6d55555011554667766d16666d1111111100d01000000500110000011511d51d666666666dd511000011155151550555016666666666
66666666666dddd6dd666dd6511115d6dd67776555666d651111110015010010016dd000000015d1555dd66776666dd110001000111d11110555156666666666
66666666666dddd6ddd6ddd66d555dd66d6677555d66666dd5611000001000500100550000000111155d6677777666d100011000500dd1111055516666666666
66666666666dddd6dd66ddd6666d5d6666d66d0d5556666d556665000000005100000d115550011115dd6677777766511111000051110d511115116666666666
666666666665dd6ddd66dddd766ddd666766655510006666d1566660011000110010051101511115d5df67777777666dddd51000500005111110116666666666
66666666666dd66ddd66dd6d6666dd766776d101d500d6666dd6666d0000001100115111101d51d1ddd66777777776666ddd5000110105111501116666666666
66666666666dd66ddd6ddddd676666776667610066006666dd55566d0000011000555511111511d555d67777777776666ddddd00015151511111116666666666
66666666666dd66dd66dddd6d76776776776d5116dd656651001005d100000505000511111d5ddddd6667777777777666dddd511000555511110016666666666
66666666666d6d66d66dddd6d6677767767551111d55566d0000001d500000505111110111116ddd666777777777677766dddd11111111111110016666666666
66666666666d6ddd666dddd66677767776511501000155556d00005550000005101111111111dd66667777777777777776661d51111111111111006666666666
6666666666666ddd66dddddd6677776776d50155100011551550055551000000051100111115dd666677777777777777766d1d51111111111111106666666666
666666666666dddd66dddddd677677677755001115100000566d51155100000000000001115dd5ddd67777777777777766dddddd111111111011106666666666
66666666666dddd666dddddd6677776777d500d550001000110541111100000001000001155dd5dd6677777777777767666ddd51111111111111116666666666
666666666665d6d66ddddddd66777767776d5115500000010505451111100060000010111dddd1dd66677777777776d6766ddd51111111111111116666666666
666666666666dd666d6ddddd666777777776d51505510000050545110110011d11111111dddd5ddd66676777777776666d65ddd1111111110111116666666666
6666666666666d666ddddddd66777777777776d5100000000001155510100111d5111111ddddddd66666777777d76666dddd5155111111110011116666666666
66666666666dd7666ddddddd66777777777777d50005110050015155000000111d11111115d6d66d666677777dd5666d66d55555551111111011116666666666
66666666666666d6ddddd66d666677677777776d555555555555555555551555555555555dddd6dddd66676766d66dd6dddddddddd5555555555556666666666
66666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666
66666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666
66666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666
66666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666
66666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666
66666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666
__sfx__
00030000324502d4500a600016000160002600016001d4301b4300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000200000c74010660137701277011670106700d6700b6700a6600a66009660086600765007640066400663005630056300462003620036200262002620026200261002610026100260002600026000260002600
000200000762007610066100661006620076200661006610066100662006610066100661006610056100561005610056100561005610046100461004610046100461004610046100361003610036100361003610
00100000000000f050080500000000000000000000000000000000000000000010001900000000000000000000000000000000000000000000e0000c000000000000000000000000a0000b000000000000000000
000200003d2503826035260322602c2502a2502924027240262302522024200232002320022200222002220022200222002220022200222002320023200232002320022200222000000000000000000000000000
000300001064015740116200961000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
