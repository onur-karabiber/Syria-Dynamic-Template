----------------------------------------------------------------
-- v9: ÇOK KATMANLI, RASTGELE AMBUSH SİSTEMİ
--
-- v8'den DEĞİŞENLER:
--
-- 1) TEK TİP (SA-10) YERİNE ÇOK TİP: SA-6, SA-8, SA-13, SA-15 de
--    ambush'a dahil edildi. İkiye ayrılıyorlar:
--      - "anchor" (SA-10): tetiklenince KALICI canlı kalır (mevcut
--        v8 davranışı, sadece stagger'lı - hepsi aynı anda değil).
--      - "mobile" (SA-6/8/13/15): gerçek "shoot-and-scoot" döngüsü.
--        Kısa süre canlı -> karanlık (relocation bekleme) -> tekrar
--        canlı... site yok edilene kadar sürer. Skynet'in kendisinde
--        böyle bir zamanlayıcı YOK (doğrulandı - skynet-iads-compiled.lua
--        içinde SAM sitesi için "random pop-up" API'si bulunmuyor,
--        goLive()/goDark() sadece anlık state değiştiriyor), bu yüzden
--        döngüyü kendi timer.scheduleFunction zincirimizle kuruyoruz.
--
-- 2) KISMİ KATILIM: her mobil site'ın ambush'a dahil olma ihtimali
--    MOBILE_AMBUSH_PARTICIPATION_CHANCE. Dahil OLMAYANLARA hiç
--    dokunulmuyor - varsayılan AUTONOMOUS_STATE_DCS_AI'da kalıyorlar,
--    yani mission başından itibaren normal Skynet otonom davranışıyla
--    (hedef görünce goLive) çalışıyorlar. Ambush'a dahil olan siteler
--    ise hardenAmbushSitesAutonomy ile DARK'a sabitleniyor (v8'deki
--    "kök sebep" notu hâlâ geçerli - bkz. aşağıdaki hardenSite).
--    Sonuç: oyuncu hangi SA-6/8/13/15'in "baştan sıcak tehdit" hangisinin
--    "pusu" olduğunu göremeden ayırt edemiyor.
--
-- 3) ZAMANLAMA RASTGELE: hem anchor hem mobile siteler ambushGo()
--    tetiklendiğinde AYNI ANDA değil, her biri kendi rastgele stagger
--    süresiyle devreye giriyor (bkz. ANCHOR_STAGGER_*, MOBILE_INITIAL_STAGGER_*).
--
-- 4) timer.scheduleFunction ID'leri saklanıyor (mobileTimerHandles):
--    ambushReset() artık bekleyen pop-up zamanlayıcılarını
--    timer.removeFunction ile gerçekten iptal ediyor - v8'de reset
--    sonrası askıda kalan bir zamanlayıcı olmazdı çünkü tek seferlikti,
--    ama mobile döngüde bu ZORUNLU: yoksa reset'ten sonra bile bir
--    site "kendi kendine" tekrar canlı olabilirdi.
--
-- KORUNAN v8 NOTLARI (hâlâ geçerli):
-- - getNatoName() "SA-XX İsim" formatını ilk boşluğa kadar kısaltıyor,
--   bu yüzden sorgular "SA-10", "SA-6" gibi kısa formda ("SA-10 Grumble"
--   DEĞİL).
-- - hardenAmbushSitesAutonomy, redIADS hazır olana kadar (60s'ye kadar)
--   1 saniyede bir kendini yeniden zamanlıyor; hazır olunca TEK SEFER
--   çalışıp duruyor (retry mantığı Skynet_Init_Main.lua'daki
--   RETRY_TIMEOUT ile tutarlı).
----------------------------------------------------------------

----------------------------------------------------------------
-- AMBUSH PROFİLLERİ
----------------------------------------------------------------
local AMBUSH_PROFILES = {
    { natoName = "SA-10", role = "anchor" },
    { natoName = "SA-6",  role = "mobile" },
    { natoName = "SA-8",  role = "mobile" },
    { natoName = "SA-13", role = "mobile" },
    { natoName = "SA-15", role = "mobile" },
}

-- Bir mobil site'ın ambush'a dahil olma ihtimali (0.0 - 1.0)
local MOBILE_AMBUSH_PARTICIPATION_CHANCE = 0.3

-- Mobile pop-up zamanlama aralıkları (saniye)
local MOBILE_INITIAL_STAGGER_MIN = 5
local MOBILE_INITIAL_STAGGER_MAX = 60
local MOBILE_LIVE_WINDOW_MIN     = 8
local MOBILE_LIVE_WINDOW_MAX     = 25
local MOBILE_COOLDOWN_MIN        = 25
local MOBILE_COOLDOWN_MAX        = 100

-- Anchor (SA-10) stagger - hepsi aynı anda değil
local ANCHOR_STAGGER_MIN = 0
local ANCHOR_STAGGER_MAX = 20

-- NOT: math.randomseed DCS'in mission-scripting sandbox'ında YOK
-- (doğrulandı: dcs.log'da "attempt to call field 'randomseed' (a nil
-- value)" hatasıyla script'in tamamı satır 75'te çöküyordu, geri
-- kalan hiçbir şey - ambushGo/ambushReset dahil - tanımlanmıyordu).
-- math.random'ın kendisi duruyor, sadece seed fonksiyonu kaldırılmış.
-- Bu yüzden DCS topluluğunun standart workaround'unu kullanıyoruz:
-- timer.getTime()'ın küsuratına göre değişken sayıda math.random()
-- çağrısını "yakıp" varsayılan sabit seed'den uzaklaşıyoruz.
do
    local burn = math.floor((timer.getTime() % 1) * 997)
    for _ = 1, burn do
        math.random()
    end
end

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local ambushFired = false               -- ambushGo tekrar tekrar tetiklenmesin
local ambushParticipants = {}           -- natoName -> {site, site, ...} (sadece ambush'a dahil olanlar)
local mobileTimerHandles = {}           -- site -> timer.scheduleFunction ID (reset'te iptal için)
local hardenComplete = false            -- hardenAmbushSitesAutonomy bitene kadar true olmaz
                                         -- (ne başarı ne de timeout/give-up ile). ambushGo() bu
                                         -- flag false iken çağrılırsa ambushParticipants henüz
                                         -- boş demektir - "gerçekten katılımcı yok" değil.

----------------------------------------------------------------
-- ERKEN SERTLEŞTİRME: AMBUSH ÖNCESİ SESSİZLİĞİ GARANTİ ET
----------------------------------------------------------------
local HARDEN_TIMEOUT = 60
local hardenStartTime = nil

local function hardenSite(site)
    site:setAutonomousBehaviour(SkynetIADSAbstractRadarElement.AUTONOMOUS_STATE_DARK)
    if not site:isDestroyed() then
        site:goDark()
    end
end

local function hardenAmbushSitesAutonomy()
    if not redIADS then
        hardenStartTime = hardenStartTime or timer.getTime()
        if timer.getTime() - hardenStartTime > HARDEN_TIMEOUT then
            env.info("[IADS] hardenAmbushSitesAutonomy: redIADS never became ready, giving up")
            hardenComplete = true
            return
        end
        timer.scheduleFunction(hardenAmbushSitesAutonomy, {}, timer.getTime() + 1)
        return
    end

    for _, profile in ipairs(AMBUSH_PROFILES) do
        local sites = redIADS:getSAMSitesByNatoName(profile.natoName)

        if profile.role == "anchor" then
            for i = 1, #sites do
                hardenSite(sites[i])
            end
            ambushParticipants[profile.natoName] = sites
            env.info(string.format(
                "[IADS] ANCHOR '%s': %d site hardened dark until ambush",
                profile.natoName, #sites
            ))
        else
            local participating = {}
            for i = 1, #sites do
                if math.random() <= MOBILE_AMBUSH_PARTICIPATION_CHANCE then
                    hardenSite(sites[i])
                    table.insert(participating, sites[i])
                end
                -- katılmayanlara dokunmuyoruz: varsayılan DCS_AI'da kalıyor
            end
            ambushParticipants[profile.natoName] = participating
            env.info(string.format(
                "[IADS] MOBILE '%s': %d/%d site ambush'a dahil edildi (dark), kalanlar normal otonom",
                profile.natoName, #participating, #sites
            ))
        end
    end

    hardenComplete = true
    env.info("[IADS] hardenAmbushSitesAutonomy: complete, ambushParticipants populated")
end

timer.scheduleFunction(hardenAmbushSitesAutonomy, {}, timer.getTime() + 1)

----------------------------------------------------------------
-- ANCHOR: KALICI CANLI (v8 ile aynı mantık, tek site için)
----------------------------------------------------------------
local function forceLiveAnchor(site)
    if site:isDestroyed() then
        return
    end
    site:setActAsEW(false)
    site:setCanEngageHARM(true)
    site:setGoLiveRangeInPercent(100)
    site:goLive()
    env.info("[IADS] ANCHOR: '" .. site:getDCSName() .. "' forced live")
end

----------------------------------------------------------------
-- MOBILE: SHOOT-AND-SCOOT POP-UP DÖNGÜSÜ
--
-- mobileGoLive/mobileGoDark birbirini çağırıyor (karşılıklı özyineleme,
-- bu yüzden ikisi de önce local olarak "forward declare" ediliyor).
-- timer.scheduleFunction'ın "return bir sayı ile aynı argümanla tekrar
-- çağrılır" davranışına GÜVENMİYORUZ (faz değişince argüman/zamanlama
-- da değişmesi gerekiyor) - bunun yerine her çağrı kendi sonraki fazını
-- YENİ bir timer.scheduleFunction ile planlayıp nil döndürüyor.
----------------------------------------------------------------
local mobileGoLive, mobileGoDark

mobileGoDark = function(params)
    local site = params.site
    mobileTimerHandles[site] = nil

    if site:isDestroyed() then
        return nil
    end

    site:goDark()
    env.info("[IADS] MOBILE POP-UP: '" .. site:getDCSName() .. "' radar OFF (relocating)")

    local cooldown = math.random(MOBILE_COOLDOWN_MIN, MOBILE_COOLDOWN_MAX)
    mobileTimerHandles[site] = timer.scheduleFunction(mobileGoLive, { site = site }, timer.getTime() + cooldown)
    return nil
end

mobileGoLive = function(params)
    local site = params.site
    mobileTimerHandles[site] = nil

    if site:isDestroyed() then
        return nil
    end

    site:setActAsEW(false)
    site:setCanEngageHARM(true)
    site:setGoLiveRangeInPercent(100)
    site:goLive()
    env.info("[IADS] MOBILE POP-UP: '" .. site:getDCSName() .. "' radar ON")

    local liveWindow = math.random(MOBILE_LIVE_WINDOW_MIN, MOBILE_LIVE_WINDOW_MAX)
    mobileTimerHandles[site] = timer.scheduleFunction(mobileGoDark, { site = site }, timer.getTime() + liveWindow)
    return nil
end

----------------------------------------------------------------
-- ANA FONKSİYON: AMBUSH
-- GLOBAL bırakılıyor - mission editöründeki bir trigger'dan
-- (DO SCRIPT: ambushGo()) çağrılabilsin diye.
----------------------------------------------------------------
function ambushGo()

    if not redIADS then
        env.info("[IADS] ambushGo: redIADS not ready yet, skipping")
        return
    end

    if ambushFired then
        env.info("[IADS] ambushGo called again - already fired, skipping")
        return
    end

    if not hardenComplete then
        -- hardenAmbushSitesAutonomy henuz bitmedi (redIADS muhtemelen hazir degildi),
        -- yani ambushParticipants henuz gercek veriyi icermiyor olabilir. ambushFired'i
        -- SET ETMEDEN cikiyoruz ki checkForBluePlayerAndAmbush pollamaya devam etsin ve
        -- harden bitince ambushGo tekrar denensin. Bu sirada ambush'a dahil olacak
        -- siteler henuz dark'a alinmamis olabilir - yani Skynet'in ham varsayilan
        -- otonom davranisiyla calisiyorlar (bkz. myIADS_v9.lua notlari).
        env.info("[IADS] ambushGo: hardening not complete yet, will retry on next poll")
        return
    end

    local totalParticipants = 0
    for _, sites in pairs(ambushParticipants) do
        totalParticipants = totalParticipants + #sites
    end

    if totalParticipants == 0 then
        env.info("[IADS] WARNING: no ambush participant sites found - check NATO names/mission setup")
        ambushFired = true
        return
    end

    ambushFired = true
    trigger.action.outText("WARNING: NEW SAM ACTIVITY DETECTED", 6)
    env.info("[IADS] AMBUSH PHASE STARTED")

    for _, profile in ipairs(AMBUSH_PROFILES) do
        local sites = ambushParticipants[profile.natoName] or {}

        for i = 1, #sites do
            local site = sites[i]
            if not site:isDestroyed() then
                if profile.role == "anchor" then
                    local delay = math.random(ANCHOR_STAGGER_MIN, ANCHOR_STAGGER_MAX)
                    timer.scheduleFunction(function(p)
                        forceLiveAnchor(p.site)
                        return nil
                    end, { site = site }, timer.getTime() + delay)
                else
                    local delay = math.random(MOBILE_INITIAL_STAGGER_MIN, MOBILE_INITIAL_STAGGER_MAX)
                    mobileTimerHandles[site] = timer.scheduleFunction(mobileGoLive, { site = site }, timer.getTime() + delay)
                end
            end
        end
    end

    env.info(string.format(
        "[IADS] AMBUSH SCHEDULED - %d site across %d NATO type(s), staggered/randomized",
        totalParticipants, #AMBUSH_PROFILES
    ))
end

----------------------------------------------------------------
-- RESET FONKSİYONU (test için)
-- Global - ayrı bir trigger'dan çağrılabilsin diye.
-- Bekleyen mobile pop-up zamanlayıcılarını GERÇEKTEN iptal ediyor
-- (timer.removeFunction) - yoksa reset sonrası bir site kendi
-- kendine tekrar canlı olabilirdi.
----------------------------------------------------------------
function ambushReset()

    if not redIADS then
        env.info("[IADS] ambushReset: redIADS not ready yet")
        return
    end

    ambushFired = false

    for site, handleId in pairs(mobileTimerHandles) do
        timer.removeFunction(handleId)
        mobileTimerHandles[site] = nil
    end

    for _, sites in pairs(ambushParticipants) do
        for i = 1, #sites do
            local site = sites[i]
            if not site:isDestroyed() then
                site:setActAsEW(true)
                site:setCanEngageHARM(false)
                site:setGoLiveRangeInPercent(30)
                site:goDark()
            end
        end
    end

    env.info("[IADS] Ambush reset - all participant sites back to silent")
end

----------------------------------------------------------------
-- OTOMATİK TETİKLEME: HERHANGİ BİR BLUE PİLOTU LIVE OLDUĞUNDA
-- (v8 ile aynı - coalition.getPlayers() polling)
----------------------------------------------------------------
local AMBUSH_PLAYER_POLL_INTERVAL = 2

local function checkForBluePlayerAndAmbush()
    if ambushFired then
        return
    end

    local players = coalition.getPlayers(coalition.side.BLUE)
    if players and #players > 0 then
        ambushGo()
    end

    if not ambushFired then
        timer.scheduleFunction(checkForBluePlayerAndAmbush, {}, timer.getTime() + AMBUSH_PLAYER_POLL_INTERVAL)
    end
end

timer.scheduleFunction(checkForBluePlayerAndAmbush, {}, timer.getTime() + AMBUSH_PLAYER_POLL_INTERVAL)
