-- Minimal Roblox Vector3 / CFrame stand-ins so RideKit maths can be tested
-- outside Roblox (same conventions: right-handed, Y up, LookVector = -Z column,
-- CFrame.Angles(x, y, z) = Rx * Ry * Rz, p1 = p0 * C0 * T * C1:Inverse()).

local V = {}
V.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		return V.new(v.X / m, v.Y / m, v.Z / m)
	end
	return V[k]
end
function V.new(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V)
end
V.__add = function(a, b) return V.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V.__sub = function(a, b) return V.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V.__unm = function(a) return V.new(-a.X, -a.Y, -a.Z) end
V.__mul = function(a, b)
	if type(a) == "number" then return V.new(a * b.X, a * b.Y, a * b.Z) end
	if type(b) == "number" then return V.new(a.X * b, a.Y * b, a.Z * b) end
	return V.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V.__div = function(a, b) return V.new(a.X / b, a.Y / b, a.Z / b) end
V.__tostring = function(a) return string.format("(%.3f, %.3f, %.3f)", a.X, a.Y, a.Z) end
function V.Dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
function V.Cross(a, b)
	return V.new(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function V.Lerp(a, b, t) return a + (b - a) * t end
V.zero = V.new(0, 0, 0)
V.xAxis = V.new(1, 0, 0)
V.yAxis = V.new(0, 1, 0)
V.zAxis = V.new(0, 0, 1)

-- CFrame: position p + rotation columns x, y, z
local C = {}
local function mk(p, x, y, z)
	return setmetatable({ p = p, x = x, y = y, z = z }, C)
end
C.__index = function(c, k)
	if k == "Position" then return c.p
	elseif k == "Rotation" then return mk(V.zero, c.x, c.y, c.z)
	elseif k == "LookVector" then return -c.z
	elseif k == "RightVector" then return c.x
	elseif k == "UpVector" then return c.y
	elseif k == "X" then return c.p.X
	elseif k == "Y" then return c.p.Y
	elseif k == "Z" then return c.p.Z
	end
	return C[k]
end
local function rotv(c, v) return c.x * v.X + c.y * v.Y + c.z * v.Z end
function C.new(a, b, c_, ...)
	if a == nil then return mk(V.zero, V.xAxis, V.yAxis, V.zAxis) end
	if type(a) == "table" then return mk(a, V.xAxis, V.yAxis, V.zAxis) end
	local r = { ... }
	if #r == 4 then -- quaternion x, y, z, w
		local x, y, z, w = r[1], r[2], r[3], r[4]
		local m = math.sqrt(x * x + y * y + z * z + w * w)
		x, y, z, w = x / m, y / m, z / m, w / m
		return mk(V.new(a, b, c_),
			V.new(1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w)),
			V.new(2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w)),
			V.new(2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y)))
	end
	if #r == 9 then -- rows R00 R01 R02 / R10 ... -> columns
		return mk(V.new(a, b, c_), V.new(r[1], r[4], r[7]), V.new(r[2], r[5], r[8]), V.new(r[3], r[6], r[9]))
	end
	return mk(V.new(a, b, c_), V.xAxis, V.yAxis, V.zAxis)
end
function C.fromMatrix(p, x, y, z)
	z = z or x:Cross(y).Unit
	return mk(p, x, y, z)
end
function C.fromAxisAngle(axis, a)
	local u = axis.Unit
	local c, s, t = math.cos(a), math.sin(a), 1 - math.cos(a)
	local function col(e)
		-- Rodrigues: R e = e cos + (u x e) sin + u (u.e)(1-cos)
		return e * c + u:Cross(e) * s + u * (u:Dot(e) * t)
	end
	return mk(V.zero, col(V.xAxis), col(V.yAxis), col(V.zAxis))
end
function C.Angles(rx, ry, rz)
	return C.fromAxisAngle(V.xAxis, rx) * C.fromAxisAngle(V.yAxis, ry) * C.fromAxisAngle(V.zAxis, rz)
end
C.fromEulerAnglesXYZ = C.Angles
function C.fromEulerAnglesYXZ(rx, ry, rz)
	return C.fromAxisAngle(V.yAxis, ry) * C.fromAxisAngle(V.xAxis, rx) * C.fromAxisAngle(V.zAxis, rz)
end
function C.lookAt(at, target, up)
	up = up or V.yAxis
	local look = (target - at).Unit
	local z = -look
	local x = up:Cross(z).Unit
	local y = z:Cross(x)
	return mk(at, x, y, z)
end
C.__mul = function(a, b)
	if getmetatable(b) == C then
		return mk(a.p + rotv(a, b.p), rotv(a, b.x), rotv(a, b.y), rotv(a, b.z))
	end
	return a.p + rotv(a, b)
end
C.__add = function(a, v) return mk(a.p + v, a.x, a.y, a.z) end
C.__sub = function(a, v) return mk(a.p - v, a.x, a.y, a.z) end
function C.Inverse(c)
	-- transpose rows
	local x = V.new(c.x.X, c.y.X, c.z.X)
	local y = V.new(c.x.Y, c.y.Y, c.z.Y)
	local z = V.new(c.x.Z, c.y.Z, c.z.Z)
	local r = mk(V.zero, x, y, z)
	return mk(-(rotv(r, c.p)), x, y, z)
end
function C.ToObjectSpace(a, b) return a:Inverse() * b end
function C.ToWorldSpace(a, b) return a * b end
function C.PointToWorldSpace(a, v) return a * v end
function C.PointToObjectSpace(a, v) return a:Inverse() * v end
function C.VectorToWorldSpace(a, v) return rotv(a, v) end
function C.VectorToObjectSpace(a, v) return rotv(a:Inverse(), v) end
local function toQuat(c)
	local m00, m01, m02 = c.x.X, c.y.X, c.z.X
	local m10, m11, m12 = c.x.Y, c.y.Y, c.z.Y
	local m20, m21, m22 = c.x.Z, c.y.Z, c.z.Z
	local tr = m00 + m11 + m22
	local x, y, z, w
	if tr > 0 then
		local s = math.sqrt(tr + 1) * 2
		w, x, y, z = 0.25 * s, (m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s
	elseif m00 > m11 and m00 > m22 then
		local s = math.sqrt(1 + m00 - m11 - m22) * 2
		w, x, y, z = (m21 - m12) / s, 0.25 * s, (m01 + m10) / s, (m02 + m20) / s
	elseif m11 > m22 then
		local s = math.sqrt(1 + m11 - m00 - m22) * 2
		w, x, y, z = (m02 - m20) / s, (m01 + m10) / s, 0.25 * s, (m12 + m21) / s
	else
		local s = math.sqrt(1 + m22 - m00 - m11) * 2
		w, x, y, z = (m10 - m01) / s, (m02 + m20) / s, (m12 + m21) / s, 0.25 * s
	end
	return x, y, z, w
end
function C.Lerp(a, b, t)
	local ax, ay, az, aw = toQuat(a)
	local bx, by, bz, bw = toQuat(b)
	local d = ax * bx + ay * by + az * bz + aw * bw
	if d < 0 then
		bx, by, bz, bw, d = -bx, -by, -bz, -bw, -d
	end
	local k0, k1
	if d > 0.9995 then
		k0, k1 = 1 - t, t
	else
		local th = math.acos(d)
		k0, k1 = math.sin((1 - t) * th) / math.sin(th), math.sin(t * th) / math.sin(th)
	end
	local p = a.p + (b.p - a.p) * t
	return C.new(p.X, p.Y, p.Z, ax * k0 + bx * k1, ay * k0 + by * k1, az * k0 + bz * k1, aw * k0 + bw * k1)
end
function C.GetComponents(c)
	return c.p.X, c.p.Y, c.p.Z, c.x.X, c.y.X, c.z.X, c.x.Y, c.y.Y, c.z.Y, c.x.Z, c.y.Z, c.z.Z
end

return { Vector3 = V, CFrame = C }
