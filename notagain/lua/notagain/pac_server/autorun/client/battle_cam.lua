local draw_line = requirex("draw_line")
local prettytext = requirex("pretty_text")

local function FrameTime()
	return math.Clamp(_G.FrameTime(), 0, 0.1)
end

battlecam = battlecam or {}

local HOOK = function(event) hook.Add(event, "battlecam", battlecam[event]) end
local UNHOOK = function(event) hook.Remove(event, "battlecam") end

function battlecam.LimitAngles(pos, dir, fov, prevpos)
	local a1 = dir:Angle()
	local a2 = (pos - prevpos):Angle()

	fov = fov / 3
	dir = a2:Forward() *-1

	a1.p = a2.p + math.Clamp(math.AngleDifference(a1.p, a2.p), -fov, fov)
	fov = fov / (ScrH()/ScrW())
	a1.y = a2.y + math.Clamp(math.AngleDifference(a1.y, a2.y), -fov, fov)

	a1.p = math.NormalizeAngle(a1.p)
	a1.y = math.NormalizeAngle(a1.y)

	return LerpVector(math.Clamp(Angle(0, a1.y, 0):Forward():DotProduct(dir), 0, 1), a1:Forward(), dir * -1)
end

function battlecam.LimitPos(pos, ply)
	local trace_forward = util.TraceHull({
		start = ply:EyePos(),
		endpos = pos,
		mins = ply:OBBMins() / 2,
		maxs = ply:OBBMaxs() / 2,
		filter = ents.FindInSphere(ply:GetPos(), 50),
		mask = MASK_SOLID_BRUSHONLY,
	})

	if trace_forward.Hit and trace_forward.Entity ~= ply and not trace_forward.Entity:IsPlayer() and not trace_forward.Entity:IsVehicle() then
		return trace_forward.HitPos + trace_forward.HitNormal * 1
	end

	return pos
end

function battlecam.FindHeadPos(ent)
	if not ent.bc_head or ent.bc_last_mdl ~= ent:GetModel() then
		for i = 0, ent:GetBoneCount() do
			local name = ent:GetBoneName(i):lower()
			if name:find("head") then
				ent.bc_head = i
				ent.bc_last_mdl = ent:GetModel()
				break
			end
		end
	end

	if ent.bc_head then
		local m = ent:GetBoneMatrix(ent.bc_head)
		if m then
			local pos = m:GetTranslation()
			if pos ~= ent:GetPos() then
				return pos
			end
		end
	end

	return ent:EyePos(), ent:EyeAngles()
end

function battlecam.CreateCrosshair()
	for _, v in pairs(ents.GetAll()) do
		if v.battlecam_crosshair then
			SafeRemoveEntity(v)
		end
	end

	local ent = ClientsideModel("models/hunter/misc/cone1x05.mdl")

	ent:SetMaterial("models/shiny")

	local mat = Matrix()
		mat:SetAngles(Angle(-90,0,0))
		mat:Scale(Vector(1,1,2) * 0.25)
		mat:Translate(Vector(0,0,-25))
	ent:EnableMatrix("RenderMultiply", mat)

	ent.RenderOverride = function(ent)
		local c = Vector(GetConVarString("cl_weaponcolor")) * 1.5

		if battlecam.selected_enemy:IsValid() then
			if battlecam.selected_enemy:IsPlayer() and battlecam.selected_enemy:GetFriendStatus() == "friend" then
				c = Vector(0.5,1,0.5)*2
			else
				c = Vector(1,0.5,0.5)*2
			end
		end

		render.SetColorModulation(c.r ^ 10, c.g ^ 10, c.b ^ 10)
			render.SetBlend(0.75)
				ent:DrawModel()
			render.SetBlend(1)
		render.SetColorModulation(1, 1, 1)
	end

	ent.battlecam_crosshair = true

	battlecam.crosshair_ent = ent
end

function battlecam.Enable()
	for _, v in pairs(ents.GetAll()) do
		if v.battlecam_crosshair then
			SafeRemoveEntity(v)
		end
	end

	HOOK("CalcView")
	HOOK("CreateMove")
	HOOK("HUDShouldDraw")
	HOOK("ShouldDrawLocalPlayer")
	HOOK("HUDPaint")

	battlecam.enabled = true
	battlecam.aim_pos = Vector()
	battlecam.aim_dir = Vector()
	battlecam.CreateCrosshair()
	battlecam.CreateHUD()
end

function battlecam.Disable()
	UNHOOK("CalcView")
	UNHOOK("CreateMove")
	UNHOOK("HUDShouldDraw")
	UNHOOK("ShouldDrawLocalPlayer")
	UNHOOK("HUDPaint")

	battlecam.enabled = false

	SafeRemoveEntity(battlecam.crosshair_ent)
	battlecam.crosshair_ent = NULL
	battlecam.selected_enemy = NULL
	battlecam.want_select = false

	battlecam.DestroyHUD()
end

function battlecam.IsEnabled()
	return battlecam.enabled
end

-- hooks

do -- view
	battlecam.cam_speed = 10

	battlecam.cam_pos = Vector()
	battlecam.cam_dir = Vector()

	local smooth_pos = Vector()
	local smooth_dir = Vector()
	local smooth_roll = 0
	local smooth_fov = 0

	local last_pos = Vector()

	function battlecam.CalcView()
		local ply = LocalPlayer()
		battlecam.aim_pos = ply:GetShootPos()

		if battlecam.want_mouse_control then
			battlecam.aim_dir = ply:GetAimVector()
		else
			battlecam.aim_dir = (ply:GetPos() - battlecam.cam_pos):GetNormalized()
		end

		if not battlecam.crosshair_ent:IsValid() then
			battlecam.CreateCrosshair()
		end

		battlecam.SetupCrosshair(battlecam.crosshair_ent)

		local delta = FrameTime()
		local target_pos = battlecam.aim_pos * 1
		local target_dir = battlecam.aim_dir * 1
		local target_fov = 60

		target_dir.z = target_dir.z / 5

		-- roll
		local target_roll = 0--math.Clamp(-smooth_dir:Angle():Right():Dot(last_pos - smooth_pos)  * delta * 40, -30, 30)
		last_pos = smooth_pos

		local hack = 1

		-- do a more usefull and less cinematic view if we're holding ctrl
		if ply:KeyDown(IN_WALK) or ply:GetMoveType() == MOVETYPE_NOCLIP then
			battlecam.aim_dir = ply:GetAimVector()
			target_dir = battlecam.aim_dir * 1
			target_pos = target_pos + battlecam.aim_dir * - 50
			target_fov = 90

			delta = delta * 2
		else
			local ent = battlecam.selected_enemy

			if ent:IsValid() then
				local size = ent:BoundingRadius() * ent:GetModelScale()
				size = size / 2

				local clean_ang = (ent:EyePos() - ply:EyePos()):Angle()
				local eye_ang = ply:EyeAngles()

				local dist = math.min(size/ent:NearestPoint(ply:GetPos()):Distance(ply:NearestPoint(ent:GetPos())), 1)

				target_pos = target_pos + LerpVector(dist, eye_ang:Right(), clean_ang:Right()) * 70-- * (ply:GetAimVector():Dot(ent:GetRight()) < 0.25 and 70 or -70)
				target_pos = target_pos + LerpVector(dist, eye_ang:Up(), clean_ang:Up()) * -10

				local head_pos = LerpVector(math.max(dist, 0.5), battlecam.FindHeadPos(ent), ent:NearestPoint(ent:EyePos()))
				target_pos = target_pos + Vector(0,0,dist*size)
				target_fov = target_fov + dist*30

				--target_dir = (ent:EyePos() - target_pos):GetNormalized()
				target_dir = (head_pos - target_pos):GetNormalized()
				--target_dir.z = target_dir.z / 10

				target_pos = target_pos + target_dir * -(200 + size)
				target_fov = target_fov - 30
			else
				target_dir = battlecam.LimitAngles(target_pos, target_dir, target_fov, smooth_pos)
				target_pos = target_pos + target_dir * -175
				target_fov = 60

				if not battlecam.want_mouse_control then
					hack = math.min((battlecam.cam_pos * Vector(1,1,0)):Distance(ply:EyePos() * Vector(1,1,0)) / 300, 1) ^ 1.5
					if hack < 0.015 and not battlecam.flip_walk then
						battlecam.flip_walk = true
						battlecam.last_flip_walk = RealTime() + 0.1
					end
				end
			end
		end

		-- smoothing
		smooth_pos = smooth_pos + ((target_pos - smooth_pos) * delta * battlecam.cam_speed * hack)
		smooth_dir = smooth_dir + ((target_dir - smooth_dir) * delta * battlecam.cam_speed)
		smooth_fov = smooth_fov + ((target_fov - smooth_fov) * delta * battlecam.cam_speed)
		smooth_roll = smooth_roll + ((target_roll - smooth_roll) * delta * battlecam.cam_speed)

		-- trace block
		smooth_pos = battlecam.LimitPos(smooth_pos, ply)

		battlecam.cam_pos = smooth_pos
		battlecam.cam_dir = smooth_dir

		-- return
		local params = {}

		params.origin = smooth_pos
		params.angles = smooth_dir:Angle()
		params.angles.r = smooth_roll
		params.fov = smooth_fov

		return params
	end
end

function battlecam.SetupCrosshair(ent)
	local enemy = battlecam.selected_enemy

	if enemy:IsValid() and not battlecam.want_mouse_control then
		ent:SetPos(enemy:EyePos() + enemy:GetUp() * (15 + math.sin(RealTime() * 20)))
		ent:SetAngles(Angle(-90,0,0))
	else
		local ply = LocalPlayer()
		local trace_res = util.QuickTrace(battlecam.aim_pos, ply:GetAimVector() * 2500, {ply, ply:GetVehicle()})

		ent:SetPos(trace_res.HitPos + Vector(0, 0, math.sin(RealTime() * 10)))
		ent:SetAngles(trace_res.HitNormal:Angle())
	end
end


do -- selection
	battlecam.selected_enemy = NULL

	local last_enemy_target = 0
	local last_enemy_scroll = 0

	function battlecam.CalcEnemySelect()
		local ply = LocalPlayer()
		local target = battlecam.selected_enemy

		if target:IsValid() then
			if ply:KeyDown(IN_USE) and last_enemy_target < RealTime() then
				battlecam.selected_enemy = NULL
				battlecam.want_select = false
				last_enemy_target = RealTime() + 0.25
			end

			if target:IsNPC() then
				for _, val in ipairs(ents.FindInSphere(target:GetPos(), 500)) do
					if val:GetRagdollOwner() == target then
						battlecam.selected_enemy = NULL
						return
					end
				end
			end

			if last_enemy_scroll < RealTime()  then
				if not target.battlecam_probably_dead then
					if input.IsKeyDown(KEY_LEFT) or input.IsKeyDown(KEY_RIGHT) then

						local found_left = {}
						local found_right = {}

						local center = target:EyePos():ToScreen()

						for _, val in ipairs(ents.FindInSphere(battlecam.cam_pos, 2500)) do
							if
								(val:IsNPC() and val ~= target) or (val:IsPlayer() and val ~= ply and val:GetFriendStatus() ~= "friend") and
								not util.TraceLine({start = ply:EyePos(), endpos = val:EyePos(), filter = {val, ply}}).Hit
							then
								local pos = val:EyePos():ToScreen()

								if pos.x > center.x then
									table.insert(found_right, {pos = pos, ent = val})
								else
									table.insert(found_left, {pos = pos, ent = val})
								end
							end
						end

						table.sort(found_right, function(a, b)
							return a.pos.x < b.pos.x
						end)

						table.sort(found_left, function(a, b)
							return a.pos.x > b.pos.x
						end)

						local found

						if input.IsKeyDown(KEY_RIGHT) then
							found = found_right[1]
							if not found or found.ent == battlecam.selected_enemy then
								found = found_left[#found_left]
							end
						else
							found = found_left[1]
							if not found or found.ent == battlecam.selected_enemy then
								found = found_right[#found_right]
							end
						end

						if found then
							battlecam.selected_enemy = found.ent

							last_enemy_scroll = RealTime() + 0.15
						end
					else
						last_enemy_scroll = 0
					end
				elseif battlecam.want_select then
					for _, val in ipairs(ents.FindInSphere(ply:GetPos(), 500)) do
						if (val:IsNPC() and not val.battlecam_probably_dead) or (val:IsPlayer() and val ~= ply and val:GetFriendStatus() ~= "friend") then
							battlecam.selected_enemy = val
							break
						end
					end
				end
			end
		elseif (ply:KeyDown(IN_USE) or input.IsKeyDown(KEY_ENTER)) and last_enemy_target < RealTime() then
			local data = ply:GetEyeTrace()

			if not data.Entity:IsValid() then
				local end_pos = battlecam.aim_pos + (battlecam.aim_dir * 2000)
				local filter = ents.FindInSphere(end_pos, 50)
				table.insert(filter, ply)
				data = util.TraceHull({
					start = battlecam.aim_pos,
					endpos = end_pos,
					mins = ply:OBBMins(),
					maxs = ply:OBBMaxs(),
					filter = filter,
				})
			end

			local ent = data.Entity

			if ent:IsValid() and (ent:IsPlayer() or ent:IsNPC()) and battlecam.selected_enemy ~= ent and ent ~= LocalPlayer() then
				battlecam.selected_enemy = ent
				battlecam.want_select = true
			else
				local done = {}
				local found = {}
				for _, val in ipairs(table.Add(ents.FindInSphere(data.HitPos, 500), ents.FindInSphere(ply:EyePos(), 500))) do
					if
						not done[val] and
						(val:IsNPC() or (val:IsPlayer() and val ~= ply and val:GetFriendStatus() ~= "friend")) and
						not util.TraceLine({start = ply:EyePos(), endpos = val:EyePos(), filter = {val, ply}}).Hit
					then
						table.insert(found, val)
						done[val] = true
					end
				end

				if found[1] then
					table.sort(found, function(a, b) return a:EyePos():Distance(ply:EyePos()) < b:EyePos():Distance(ply:EyePos()) end)
					battlecam.selected_enemy = found[1]
					battlecam.want_select = true
				end
			end

			last_enemy_target = RealTime() + 0.25
		end
	end
end

battlecam.weapon_i = 1
battlecam.last_select = 0

function battlecam.GetWeapons()
	local ply = LocalPlayer()
	battlecam.weapons = table.ClearKeys(ply:GetWeapons())
	table.sort(battlecam.weapons, function(a, b)return a:EntIndex() < b:EntIndex() end)
	return battlecam.weapons
end

function battlecam.GetWeaponIndex()
	return battlecam.weapon_i%#battlecam.GetWeapons() + 1
end

do
	local smooth_dir = Vector()
	battlecam.want_mouse_control_time = 0

	function battlecam.CreateMove(ucmd)
		local ply = LocalPlayer()
		if not ply:Alive() or vgui.CursorVisible() then return end

		battlecam.CalcEnemySelect()

		local ent = battlecam.selected_enemy

		if ent:IsValid() and not battlecam.want_mouse_control then

			if ent:IsPlayer() and (not ent:Alive() or not ply:Alive()) then
				battlecam.selected_enemy = NULL
			end

			local head_pos = battlecam.FindHeadPos(ent)
			local aim_ang = (head_pos - ply:GetShootPos()):Angle()

			aim_ang.p = math.NormalizeAngle(aim_ang.p)
			aim_ang.y = math.NormalizeAngle(aim_ang.y)
			aim_ang.r = 0

			ucmd:SetViewAngles(aim_ang)
		end

		if battlecam.last_select < RealTime() then
			if input.IsKeyDown(KEY_DOWN) then
				battlecam.weapon_i = battlecam.weapon_i + 1
				battlecam.last_select = RealTime() + 0.15
			elseif input.IsKeyDown(KEY_UP) then
				battlecam.weapon_i = battlecam.weapon_i - 1
				battlecam.last_select = RealTime() + 0.15
			end

			local delta = ucmd:GetMouseWheel()
			if delta ~= 0 then
				battlecam.weapon_i = battlecam.weapon_i - delta
				battlecam.last_select = RealTime() + 0.01
			end
		end

		local wep = battlecam.GetWeapons()[battlecam.GetWeaponIndex()]

		if wep then
			ucmd:SelectWeapon(wep)
		end

		if input.IsKeyDown(KEY_ENTER) then
			ucmd:SetButtons(ucmd:GetButtons() + IN_ATTACK)
			return
		end

		if ucmd:GetMouseX() ~= 0 or ucmd:GetMouseY() ~= 0 then
			battlecam.want_mouse_control = true
			battlecam.want_mouse_control_time = RealTime() + 0.5
		end

		if (not ent:IsValid() or (ply:KeyDown(IN_SPEED) and not ply:KeyDown(IN_FORWARD))) and not ply:KeyDown(IN_WALK) and ply:GetMoveType() ~= MOVETYPE_NOCLIP and not battlecam.want_mouse_control then

			local dir = Vector()

			if ply:KeyDown(IN_MOVELEFT) then
				dir = (ply:GetPos() - battlecam.cam_pos):Angle():Right() * -1
			elseif ply:KeyDown(IN_MOVERIGHT) then
				dir = (ply:GetPos() - battlecam.cam_pos):Angle():Right()
			end

			if ply:KeyDown(IN_FORWARD) then
				dir = dir + (ply:GetPos() - battlecam.cam_pos):Angle():Forward()

				if battlecam.flip_walk then
					dir = dir * -1
				end
			elseif ply:KeyDown(IN_BACK) then
				dir = dir + (ply:GetPos() - battlecam.cam_pos):Angle():Forward() * -1

				if battlecam.flip_walk then
					dir = dir * -1
				end
			else
				battlecam.flip_walk = nil
			end

			dir.z = 0

			if dir ~= Vector(0,0,0) then
				smooth_dir = smooth_dir + ((dir - smooth_dir) * FrameTime() * 10)
				ucmd:SetViewAngles(smooth_dir:Angle())
				ucmd:SetForwardMove(1000)
				ucmd:SetSideMove(0)
			end
		end

		if battlecam.want_mouse_control and not ply:KeyDown(IN_MOVELEFT) and not ply:KeyDown(IN_MOVERIGHT) and not ply:KeyDown(IN_FORWARD) and not ply:KeyDown(IN_BACK) and battlecam.want_mouse_control_time < RealTime() then
			battlecam.want_mouse_control = false
		end
	end
end

function battlecam.HUDShouldDraw(hud_type)
	if
		hud_type == "CHudCrosshair" or
		hud_type == "CHudHealth" or
		hud_type == "CHudBattery" or
		hud_type == "CHudAmmo" or
		hud_type == "CHudSecondaryAmmo" or
		hud_type == "CHudWeaponSelection"
	then
		return false
	end
end

function battlecam.ShouldDrawLocalPlayer()
	return true
end

local line_mat = Material("particle/Particle_Glow_04")

local line_width = 8
local line_height = -31
local max_bounce = 2
local bounce_plane_height = 5

local life_time = 3
local hitmarks = {}
local height_offset = 0

battlecam.healthbars = battlecam.healthbars or {}

local health_mat = Material("gui/gradient")

local function draw_bar(x, y, w, h, cur, max, fade, fr,fg,fb, br,bg,bb, thick)
	fade = fade or 1
	w = w or 256

	fr = fr or 0
	fg = fg or 255
	fb = fb or 0

	br = br or 255
	bg = bg or 0
	bb = bb or 0

	thick = thick or 6

	surface.SetDrawColor(50, 50, 50, 255 * fade)
	draw_line(
		x - 5,
		y + h - 2,

		x + w - 5,
		y + h - 2,

		thick + 3
	)

	surface.SetMaterial(health_mat)

	surface.SetDrawColor(255, 255, 255, 255 * fade)
	draw_line(
		x - 5,
		y + h - 2,

		x + w - 5,
		y + h - 2,

		thick + 3,
		true
	)

	surface.SetDrawColor(br, bg, bb, 255 * fade)
	draw_line(
		x - 5,
		y + h - 2,

		x + w - 5,
		y + h - 2,

		thick,
		true
	)

	surface.SetDrawColor(fr, fg, fb, 255 * fade)
	draw_line(
		x - 5,
		y + h - 2,

		(x + (w * math.Clamp(cur / max, 0, 1))) - 5,
		y + h - 2,

		thick,
		true
	)
end

do
	battlecam.entities = battlecam.entities or {}

	local function create_ent(path, pos, ang, scale, tex)
		local ent = ClientsideModel(path)
		ent:SetNoDraw(true)
		ent:SetPos(pos)
		ent:SetAngles(ang)

		if type(scale) == "Vector" then
			local m = Matrix()
			m:Scale(Vector(scale))
			ent:EnableMatrix("RenderMultiply", m)
		else
			ent:SetModelScale(scale or 1)
		end
		ent:SetLOD(0)

		local mat

		if tex then
			mat = CreateMaterial("battlecam_" .. path ..tostring({}), "VertexLitGeneric", {["$basetexture"] = tex})
		else
			mat = CreateMaterial("battlecam_" .. path ..tostring({}), "VertexLitGeneric")
			mat:SetTexture("$basetexture", Material(ent:GetMaterials()[1]):GetTexture("$basetexture"))
		end

		function ent:RenderOverride()
			render.MaterialOverride(mat)
			ent:DrawModel()
			render.MaterialOverride()
		end

		table.insert(battlecam.entities, ent)

		return ent
	end

	function battlecam.DestroyHUD()
		for _, ent in pairs(battlecam.entities) do
			SafeRemoveEntity(ent)
		end
		battlecam.entities = {}
	end

	function battlecam.CreateHUD()
		local sx = ScrW() / 1980
		local sy = ScrH() / 1050

		local x = 65*sx
		local y = ScrH() - 140*sy

		x = x * 1/sx
		y = y * 1/sy

		local combine_scanner_ent = create_ent("models/combine_scanner.mdl", Vector(x+150,y-38,1000), Angle(-90,-90-45,0), 10)
		combine_scanner_ent:SetSequence(combine_scanner_ent:LookupSequence("flare"))

		local suit_charger_ent = create_ent("models/props_combine/suit_charger001.mdl", Vector(x+350,y-20,0), Angle(-90,0,0), 10)
		suit_charger_ent:SetSequence(suit_charger_ent:LookupSequence("idle"))

		local health_bar_bg = create_ent("models/props_combine/combine_train02a.mdl", Vector(x+645,y-5,300), Angle(0,-90,0), Vector(0.2,1.27,1))
		local health_bar = create_ent("models/hunter/plates/plate1x1.mdl", Vector(x+640,y-5,600), Angle(90,90,0), Vector(1,3,0.7) * 6, "decals/light")
		local mana_bar_bg = create_ent("models/props_combine/combine_train02a.mdl", Vector(x+445,y-20,300), Angle(0,-90,0), Vector(0.125,0.75,1))
		local mana_bar = create_ent("models/hunter/plates/plate1x1.mdl", Vector(x+640,y-20,600), Angle(90,90,0), Vector(1,3,0.3) * 6, "decals/light")

		local smooth_hp = 100
		local smooth_armor = 100
		local time = 0

		function battlecam.DrawHPMP()
			local ply = LocalPlayer()
			local cur_hp = ply:Health()
			local cur_armor = ply:Armor()

			smooth_hp = smooth_hp + ((cur_hp - smooth_hp) * FrameTime() * 5)
			smooth_armor = smooth_armor + ((cur_armor - smooth_armor) * FrameTime() * 5)

			local max_hp = ply:GetMaxHealth()
			local max_armor = 100

			local fract = smooth_hp / max_hp
			fract = fract ^ 0.3

			combine_scanner_ent:SetCycle((-fract+1)^0.25)
			suit_charger_ent:SetCycle(fract)

			render.SetColorModulation(Lerp(fract, math.sin(time)+1.5, 1),Lerp(fract, 0.25, 1),Lerp(fract, 0.25, 1))
			time = time + FrameTime()*(7/fract)

			render.SuppressEngineLighting(true)

			cam.StartOrthoView(0,0,ScrW()*(1/sx),ScrH()*(1/sy))

				render.CullMode(MATERIAL_CULLMODE_CW)
					render.PushCustomClipPlane(Vector(0,1,0), 500)
						suit_charger_ent:DrawModel()
					render.PopCustomClipPlane()
					combine_scanner_ent:DrawModel()
				render.CullMode(MATERIAL_CULLMODE_CCW)

				-- armor
				render.SetColorModulation(1,1,1,1)
				mana_bar_bg:DrawModel()

				render.SetColorModulation(0.5,0.65,1.75)
				render.PushCustomClipPlane(Vector(-1,0,0), (-670 - x) * math.min(smooth_armor/max_armor, 1))
					mana_bar:DrawModel()
				render.PopCustomClipPlane()

				-- health
				render.SetColorModulation(1,1,1,1)
				health_bar_bg:DrawModel()

				render.SetColorModulation(0.5,1.75,0.65)
				render.PushCustomClipPlane(Vector(-1,0,0), (-1000 - x) * math.min(smooth_hp/max_hp, 1))
					health_bar:DrawModel()
				render.PopCustomClipPlane()

				render.SetColorModulation(1,1,1)


				prettytext.Draw(math.Round(smooth_hp), x + 280, y + 5, "Candara", 30, 30, 2, Color(255, 255, 255, 200))

			cam.EndOrthoView()
		end

		local x = ScrW() - 220*sx
		local y = ScrH() - 175*sy

		x = x * 1/sx
		y = y * 1/sy

		local weapon_menu = create_ent("models/combine_helicopter/helicopter_bomb01.mdl", Vector(x,y), Angle(0,90,0), 7)
		local weapon_menu2 = create_ent("models/combine_dropship_container.mdl", Vector(x-80,y, -500), Angle(90,0,0), 1.9)

		local weapon_selection = {}
		for i= 1,32 do
			weapon_selection[i] = create_ent("models/props_combine/combinetrain01a.mdl", Vector(x-5, y - 5, -500), Angle(0,0,0), Vector(0.8,0.45,1) * 0.5)
		end

		local smooth_i = 0

		local font_lookup = {
			["Pistol"] = "p",
			["SMG1"] = "\x72",
			["SMG1_Grenade"] = "\x5F",
			["357"] = "\x71",
			["AR2"] = "u",
			["AR2AltFire"] = "z",
			["Buckshot"] = "s",
			["XBowBolt"] = "w",
			["Grenade"] = "v",
			["RPG_Round"] = "x",
			["slam"] = "o",

			["weapon_smg1"] = "&",
			["weapon_shotgun"] = "(",
			["weapon_pistol"] = "%",
			["weapon_357"] = "$",
			["weapon_crossbow"] = ")",
			["weapon_ar2"] = ":",
			["weapon_frag"] = "_",
			["weapon_rpg"] = ";",
			["weapon_crowbar"] = "^",
			["weapon_stunstick"] = "n",
			["weapon_physcannon"] = "!",
			["weapon_physgun"] = "h",
			["weapon_bugbait"] = "~",
			["weapon_slam"] = "o",
		}

		function battlecam.DrawWeaponSelection()
			local ply = LocalPlayer()
			local weapons = battlecam.GetWeapons()

			if not weapons[1] then return end

			local max_hp = ply:GetMaxHealth()
			local fract = smooth_hp / max_hp
			fract = fract ^ 0.3

			cam.StartOrthoView(0,0,ScrW()*(1/sx),ScrH()*(1/sy))
				render.CullMode(MATERIAL_CULLMODE_CW)

				render.PushCustomClipPlane(Vector(-1,0,0), -x)
					for i, wep in ipairs(weapons) do
						local real_i = i

						i = i + -battlecam.weapon_i
						i = i - #weapons / 2
						i = i + (0.25 * #weapons) - 1
						i = i / #weapons
						i = i * math.pi * 2

						wep.battlecam_smooth_i = wep.battlecam_smooth_i or 0
						wep.battlecam_smooth_i = wep.battlecam_smooth_i + ((i - wep.battlecam_smooth_i) * FrameTime() * 10)

						local i = wep.battlecam_smooth_i

						local x = x + math.sin(i) * 200
						local y = y + math.cos(i) * 50

						local ent = weapon_selection[real_i%#weapon_selection + 1]
						ent:SetRenderOrigin(Vector(x-5, y - 5, x*-40))
						ent:DrawModel()

						local name = wep:GetClass()

						if language.GetPhrase(name) then
							name = language.GetPhrase(name)
						end

						render.CullMode(MATERIAL_CULLMODE_CCW)
							surface.SetAlphaMultiplier(math.abs(math.sin(i)) ^ 3)
							prettytext.Draw(name, x-120, y-19, "Candara", 26, 0, 4, Color(255, 255, 255, 150))
							surface.SetAlphaMultiplier(1)
						render.CullMode(MATERIAL_CULLMODE_CW)
					end
				render.PopCustomClipPlane()

				weapon_menu:DrawModel()
				weapon_menu:SetModelScale(7)
				weapon_menu2:DrawModel()

				render.CullMode(MATERIAL_CULLMODE_CCW)

				cam.IgnoreZ(true)

				local wep = LocalPlayer():GetActiveWeapon()
				if wep:IsValid() then
					local size = 200
					if wep.DrawWeaponSelection then
						wep:DrawWeaponSelection(x-size/2,y-size/4, size, size, 255)
					else
						local icon = font_lookup[wep:GetClass()]
						if icon then
							local w,h = prettytext.GetTextSize(icon, "HALFLIFE2", 150, 0)
							local m = Matrix()
							m:Translate(Vector(x-w/2 + w, y-h/2, 0))
							m:Scale(Vector(-1,1,1))
							cam.PushModelMatrix(m)
							render.CullMode(MATERIAL_CULLMODE_CW)
								surface.SetAlphaMultiplier(0.5)
								prettytext.Draw(icon, 0, -12, "HALFLIFE2", 1000, 0, 10, Color(200, 255, 255, 255))
								surface.SetAlphaMultiplier(1)
							render.CullMode(MATERIAL_CULLMODE_CCW)
							cam.PopModelMatrix()
						end
					end
				end
			cam.EndOrthoView()
		end
	end
end

function battlecam.HUDPaint()
	surface.SetDrawColor(255,255,255,255)
	surface.SetAlphaMultiplier(1)
	--[[
	local grid_size = 9
	for i = 0, grid_size do
		i = i * ScrH() / grid_size
		surface.DrawLine(0,i, ScrW(),i)
	end
	for i = 0, grid_size do
		i = i * ScrW() / grid_size
		surface.DrawLine(i,0, i,ScrH())
	end]]

	surface.DisableClipping(true)
	render.SuppressEngineLighting(true)
	render.SetColorModulation(1,1,1)

	battlecam.DrawHPMP()
	battlecam.DrawWeaponSelection()

	render.SetColorModulation(1,1,1)
	render.SuppressEngineLighting(false)
	cam.IgnoreZ(false)
	surface.DisableClipping(false)
end

concommand.Add("battlecam", function()
	if battlecam.IsEnabled() then
		battlecam.Disable()
	else
		battlecam.Enable()
	end
end)

if battlecam.IsEnabled() then
	battlecam.Disable()
	battlecam.Enable()
end