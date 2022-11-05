--[[
Copyright (C) GtX (Andy), 2022

Author: GtX | Andy
Date: 14.02.2022
Revision: FS22-02

Contact:
https://forum.giants-software.com
https://github.com/GtX-Andy

Important:
Free for use in mods (FS22 Only) - no permission needed.
No modifications may be made to this script, including conversion to other game versions without written permission from GtX | Andy
Copying or removing any part of this code for external use without written permission from GtX | Andy is prohibited.

Frei verwendbar (Nur LS22) - keine erlaubnis nötig
Ohne schriftliche Genehmigung von GtX | Andy dürfen keine Änderungen an diesem Skript vorgenommen werden, einschließlich der Konvertierung in andere Spielversionen
Das Kopieren oder Entfernen irgendeines Teils dieses Codes zur externen Verwendung ohne schriftliche Genehmigung von GtX | Andy ist verboten.
]]

BeaconLightAnimation = {}

local modName = g_currentModName or ""
local modDirectory = g_currentModDirectory or ""

local customClassName = modName .. ".BeaconLightAnimation"
local BeaconLightAnimation_mt = Class(BeaconLightAnimation, Animation)

function BeaconLightAnimation.new(customMt)
    local self = Animation.new(customMt or BeaconLightAnimation_mt)

    self.node = nil
    self.beaconActive = false
    self.isDeleted = false

    return self
end

function BeaconLightAnimation:load(xmlFile, key, components, owner, i3dMappings)
    if not xmlFile:hasProperty(key) then
        return nil
    end

    self.owner = owner
    self.node = xmlFile:getValue(key .. "#node", nil, components, i3dMappings)

    if self.node == nil then
        Logging.xmlWarning(xmlFile, "Missing node for beacon light animation '%s'!", key)

        return nil
    end

    local lightXmlFilename = xmlFile:getValue(key .. "#filename")

    self.speed = xmlFile:getValue(key .. "#speed")
    self.realLightRange = xmlFile:getValue(key .. "#realLightRange", 1)
    self.intensity = xmlFile:getValue(key .. "#intensity")

    self.hasRealBeaconLights = self.realLightRange > 0 and g_gameSettings:getValue("realBeaconLights")

    if lightXmlFilename ~= nil then
        lightXmlFilename = Utils.getFilename(lightXmlFilename, modDirectory)

        self.beaconLightXMLFile = XMLFile.load("beaconLightXML", lightXmlFilename, Lights.beaconLightXMLSchema)

        if self.beaconLightXMLFile ~= nil then
            local i3dFilename = self.beaconLightXMLFile:getValue("beaconLight.filename")

            if i3dFilename ~= nil then
                i3dFilename = Utils.getFilename(i3dFilename, modDirectory)

                self.sharedLoadRequestId = g_i3DManager:loadSharedI3DFileAsync(i3dFilename, false, false, self.onSharedBeaconFileLoaded, self, nil)
            end
        end
    else
        self.lightShaderNode = self.node
        self.realLightNode = xmlFile:getValue(key .. ".realLight#node", nil, components, i3dMappings)
        self.rotatorNode = xmlFile:getValue(key .. ".rotator#node", nil, components, i3dMappings)
        self.multiBlink = xmlFile:getValue(key .. "#multiBlink", false)

        if self.realLightNode ~= nil then
            self.defaultColour = {getLightColor(self.realLightNode)}
            self.defaultLightRange = getLightRange(self.realLightNode)

            setVisibility(self.realLightNode, false)
            setLightRange(self.realLightNode, self.defaultLightRange * self.realLightRange)
        end
    end

    return self
end

function BeaconLightAnimation:delete()
    if self.beaconLightXMLFile ~= nil then
        self.beaconLightXMLFile:delete()
        self.beaconLightXMLFile = nil
    end

    if self.sharedLoadRequestId ~= nil then
        g_i3DManager:releaseSharedI3DFile(self.sharedLoadRequestId)
        self.sharedLoadRequestId = nil
    end

    self.isDeleted = true

    BeaconLightAnimation:superClass().delete(self)
end

function BeaconLightAnimation:update(dt)
    BeaconLightAnimation:superClass().update(self, dt)

    if self.beaconActive then
        if self.rotatorNode ~= nil then
            rotate(self.rotatorNode, 0, self.speed * dt, 0)
        end

        if self.hasRealBeaconLights and self.realLightNode ~= nil and self.multiBlink then
            local x, y, z, _ = getShaderParameter(self.lightShaderNode or self.beaconLights[1].lightShaderNode, "blinkOffset")

            local cTime_s = getShaderTimeSec()
            local alpha = MathUtil.clamp(math.sin(cTime_s * z) - math.max(cTime_s * z % ((x * 2 + y * 2) * math.pi) - (x * 2 - 1) * math.pi, 0) + 0.2, 0, 1)

            local r, g, b = self.defaultColour[1], self.defaultColour[2], self.defaultColour[3]

            setLightColor(self.realLightNode, r * alpha, g * alpha, b * alpha)

            for i = 0, getNumOfChildren(self.realLightNode) - 1 do
                setLightColor(getChildAt(self.realLightNode, i), r * alpha, g * alpha, b * alpha)
            end
        end
    end
end

function BeaconLightAnimation:isRunning()
    return self.beaconActive
end

function BeaconLightAnimation:start()
    if not self.beaconActive then
        self:setBeaconLightActive(true)

        return true
    end

    return false
end

function BeaconLightAnimation:stop()
    if self.beaconActive then
        self:setBeaconLightActive(false)

        return true
    end

    return false
end

function BeaconLightAnimation:reset()
    self:setBeaconLightActive(false)
end

function BeaconLightAnimation:setBeaconLightActive(beaconActive)
    self.beaconActive = beaconActive

    if self.hasRealBeaconLights and self.realLightNode ~= nil then
        setVisibility(self.realLightNode, beaconActive)
    end

    if self.lightNode ~= nil then
        setVisibility(self.lightNode, beaconActive)
    end

    if self.lightShaderNode ~= nil then
        local value = 0

        if beaconActive then
            value = 1 * self.intensity
        end

        local _, y, z, w = getShaderParameter(self.lightShaderNode, "lightControl")

        setShaderParameter(self.lightShaderNode, "lightControl", value, y, z, w, false)
    end
end

function BeaconLightAnimation:onSharedBeaconFileLoaded(i3dNode, failedReason, args)
    local xmlFile = self.beaconLightXMLFile

    if i3dNode ~= nil and i3dNode ~= 0 then
        if not self.isDeleted then
            local rootNode = xmlFile:getValue("beaconLight.rootNode#node", nil, i3dNode)
            local lightNode = xmlFile:getValue("beaconLight.light#node", nil, i3dNode)
            local lightShaderNode = xmlFile:getValue("beaconLight.light#shaderNode", nil, i3dNode)

            if rootNode ~= nil and (lightNode ~= nil or lightShaderNode ~= nil) then
                self.rootNode = rootNode
                self.lightNode = lightNode
                self.lightShaderNode = lightShaderNode

                self.realLightNode = xmlFile:getValue("beaconLight.realLight#node", nil, i3dNode)
                self.rotatorNode = xmlFile:getValue("beaconLight.rotator#node", nil, i3dNode)
                self.speed = xmlFile:getValue("beaconLight.rotator#speed", self.speed or 0.015)
                self.intensity = xmlFile:getValue("beaconLight.light#intensity", self.intensity or 1000)
                self.multiBlink = xmlFile:getValue("beaconLight.light#multiBlink", false)

                link(self.node, rootNode)
                setTranslation(rootNode, 0, 0, 0)

                if self.realLightNode ~= nil then
                    self.defaultColour = {getLightColor(self.realLightNode)}
                    self.defaultLightRange = getLightRange(self.realLightNode)

                    setVisibility(self.realLightNode, false)
                    setLightRange(self.realLightNode, self.defaultLightRange * self.realLightRange)
                end

                if lightNode ~= nil then
                    setVisibility(lightNode, false)
                end

                if lightShaderNode ~= nil then
                    local _, y, z, w = getShaderParameter(lightShaderNode, "lightControl")

                    setShaderParameter(lightShaderNode, "lightControl", 0, y, z, w, false)
                end

                if self.speed > 0 and self.rotatorNode ~= nil then
                    setRotation(self.rotatorNode, 0, math.random(0, math.pi * 2), 0)
                end

                if self.beaconActive then
                    self:setBeaconLightActive(true)
                end
            end
        end

        delete(i3dNode)
    end

    self.beaconLightXMLFile:delete()
    self.beaconLightXMLFile = nil
end

function BeaconLightAnimation.registerAnimationClassXMLPaths(schema, basePath)
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".animationNode(?)#node", "(BeaconLightAnimation) Link node when filename is given or beacon node")
    schema:register(XMLValueType.STRING, basePath .. ".animationNode(?)#filename", "(BeaconLightAnimation) Beacon light xml file")
    schema:register(XMLValueType.FLOAT, basePath .. ".animationNode(?)#speed", "(BeaconLightAnimation) Beacon light speed override")
    schema:register(XMLValueType.FLOAT, basePath .. ".animationNode(?)#realLightRange", "(BeaconLightAnimation) Factor that is applied on real light range of the beacon light", 1)
    schema:register(XMLValueType.INT, basePath .. ".animationNode(?)#intensity", "(BeaconLightAnimation) Beacon light intensity override")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".animationNode(?).realLight#node", "(BeaconLightAnimation) Real light node")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".animationNode(?).rotator#node", "(BeaconLightAnimation) Rotator node")
    schema:register(XMLValueType.BOOL, basePath .. ".animationNode(?)#multiBlink", "(BeaconLightAnimation) Is multiblink light")
end

-- There is no way to add custom animation nodes to registration without manually doing this, here is a work around.
-- Other modders are free to use the below code as part of their own Animation scripts but please do not modify as it must support all mod scripts and no need for multiple appended functions
if AnimationManager.CUSTOM_CLASSES_TO_REGISTER_XML_PATH == nil then
    AnimationManager.CUSTOM_CLASSES_TO_REGISTER_XML_PATH = {}

    AnimationManager.registerAnimationNodesXMLPaths = Utils.appendedFunction(AnimationManager.registerAnimationNodesXMLPaths, function(schema, basePath)
        local classes = AnimationManager.CUSTOM_CLASSES_TO_REGISTER_XML_PATH

        if classes == nil and g_animationManager.registeredAnimationClasses ~= nil then
            classes = g_animationManager.registeredAnimationClasses
        end

        if classes ~= nil then
            schema:setXMLSharedRegistration("AnimationNode", basePath)

            for className, animationClass in pairs (classes) do
                if string.find(tostring(className), ".") and rawget(animationClass, "registerAnimationClassXMLPaths") then
                    animationClass.registerAnimationClassXMLPaths(schema, basePath)
                end
            end

            schema:setXMLSharedRegistration()
        end
    end)
end

-- Add class to the table so it will be available
AnimationManager.CUSTOM_CLASSES_TO_REGISTER_XML_PATH[customClassName] = BeaconLightAnimation

-- Add class directly so that the class name includes the mod environment for no conflicts
-- @Giants do not localise this correctly for animations using 'g_animationManager:registerAnimationClass', it is only done for Effects as of v1.4.1.0
if g_animationManager.registeredAnimationClasses ~= nil then
    g_animationManager.registeredAnimationClasses[customClassName] = BeaconLightAnimation
else
    Logging.error("Failed to register animation class '%s' due to base game code changes. Please report: https://github.com/GtX-Andy", customClassName)
end
