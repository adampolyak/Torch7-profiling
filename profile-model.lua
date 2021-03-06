require 'nn'
require 'xlua'
require 'sys'
local lapp = assert(require('pl.lapp'))
local profile = assert(require('src/profiler'))
local spatial = assert(require('src/spatial'))

local pf = function(...) print(string.format(...)) end
local r = sys.COLORS.red
local g = sys.COLORS.green
local n = sys.COLORS.none
local THIS = sys.COLORS.blue .. 'THIS' .. n

local opt = lapp [[
 -m, --model      (default '')   Path & filename of network model to profile
 -p, --platform   (default cpu)  Select profiling platform (cpu|cuda|nnx)
 -c, --channel    (default 0)    Input image channel number
 -e, --eye        (default 0)    Network eye
 -w, --width      (default 0)    Image width
 -h, --height     (default 0)    Image height
 -i, --iter       (default 10)   Averaging iterations
 -s, --save       (default -)    Save the float model to file as <model.net.ascii>in
                                 [a]scii or as <model.net> in [b]inary format (a|b)
]]
torch.setdefaulttensortype('torch.FloatTensor')


if string.find(opt.model, '.lua', #opt.model-4) then
   model = assert(require('./'..opt.model))
   pf('Building %s model from model...\n', r..model.name..n)
   net = model:mknet()
   eye = model.eye
elseif string.find(opt.model, '.net', #opt.model-4) then
   model = { channel = 3, name = 'Trained binary network' }
   pf('Loading %s model from binary file...\n', r..model.name..n)
   net = torch.load(opt.model, 'binary')
elseif string.find(opt.model, '.net.ascii', #opt.model-10) then
   model = { channel = 3, name = 'Trained ascii network' }
   pf('Loading %s model from ascii file...\n', r..model.name..n)
   net = torch.load(opt.model, 'ascii')
else
   error('Network named not recognized')
end

if opt.channel ~= 0 then
   model.channel = opt.channel
end

eye = eye or 100
if opt.eye ~= 0 then
   eye = opt.eye
end

local width    = (opt.width ~= 0) and opt.width or eye
local height   = (opt.height ~= 0) and opt.height or width

img = torch.FloatTensor(model.channel, height, width)


-- spatial net conversion
if (width ~= eye) or (height ~= eye) then
   if (opt.platform == 'nnx') then
      print('Convert network to nn-X spatial')
      net = spatial.net_spatial_mlp(net, torch.Tensor(model.channel, eye, eye))
   else
      print('Convert network to cpu spatial')
      net = spatial.net_spatial(net, torch.Tensor(model.channel, eye, eye))
   end
end


if opt.save == 'a' then
   pf('Saving model as model.net.ascii... ')
   torch.save('model.net.ascii', net, 'ascii')
   pf('Done.\n')
elseif opt.save == 'b' then
   pf('Saving model as model.net... ')
   torch.save('model.net', net)
   pf('Done.\n')
end


-- calculate the number of operations performed by the network
if model.def and (opt.platform == 'nnx') then
   ops = profile:calc_ops(model.def, model.channel, {
      width  = img:size(3), height = img:size(2),
   })
else
   ops = profile:ops(net, img)
end
ops_total = ops.conv + ops.pool + ops.mlp

pf('   Total number of neurons: %d', ops.neurons)
pf('   Total number of trainable parameters: %d', net:getParameters():size(1))
pf('   Operations estimation for square image size: %d X %d', width, height)
pf('    + Total: %.2f G-Ops', ops_total * 1e-9)
pf('    + Conv/Pool/MLP: %.2fG/%.2fk/%.2fM(-Ops)\n',
   ops.conv * 1e-9, ops.pool * 1e-3, ops.mlp * 1e-6)


-- time and average over a number of iterations
pf('Profiling %s, %d iterations', r..model.name..n, opt.iter)
time = profile:time(net, img, opt.iter, opt.platform)

local d = g..'CPU'..n
if 'cuda' == opt.platform then
   d = g..'GPU'..n
elseif 'nnx' == opt.platform then
   d = g..'nnX'..n
end

pf('   Forward average time on %s %s: %.2f ms', THIS, d, time.total * 1e3)
if (time.conv ~= 0) and (time.mlp ~= 0) then
   pf('    + Convolution time: %.2f ms', time.conv * 1e3)
   pf('    + MLP time: %.2f ms', time.mlp * 1e3)
end

pf('   Performance for %s %s: %.2f G-Ops/s\n', THIS, d, ops_total * 1e-9 / time.total)
