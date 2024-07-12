module FRP.Rhine.Discord where

import Control.Monad.Trans.Reader (withReaderT)
import Data.Functor (void)
import Data.Text (Text)
import Discord (DiscordHandler, RunDiscordOpts (..), runDiscord)
import Discord.Types (Event, GatewayIntent)
import FRP.Rhine
import UnliftIO.Concurrent (forkIO, writeChan)
import Prelude

type DiscordEventClock = EventClock Event

type DiscordLogClock = EventClock Text

flowDiscord
    :: forall cl st
     . ( Clock DiscordHandler cl
       , Clock DiscordHandler (In cl)
       , Clock DiscordHandler (Out cl)
       , GetClockProxy cl
       , Time cl ~ Time DiscordEventClock
       , Time (In cl) ~ Time cl
       , Time (Out cl) ~ Time cl
       )
    => Text
    -> GatewayIntent
    -> st
    -> ClSF DiscordHandler DiscordEventClock st st
    -> ClSF DiscordHandler DiscordLogClock st st
    -> Rhine DiscordHandler cl st st
    -> IO ()
flowDiscord discordToken discordGatewayIntent initialState handleEvents handleLog simRh = do
    eventChan <- newChan
    logChan <- newChan
    let hoistClock :: (Monad m, Time cl1 ~ Time cl2, Tag cl1 ~ Tag cl2) => ClSF m cl1 a b -> ClSF m cl2 a b
        hoistClock = hoistS $ withReaderT . retag $ id
        eventsRh = hoistClock handleEvents @@ eventClockOn @DiscordHandler eventChan
        logRh = hoistClock handleLog @@ eventClockOn @DiscordHandler logChan
        mainRh =
            feedbackRhine
                (keepLast initialState)
                (snd ^>>@ ((eventsRh |@| logRh) |@| simRh) @>>^ ((),))
    void . runDiscord $
        RunDiscordOpts
            { discordToken
            , discordOnStart = void . forkIO . flow $ mainRh
            , discordOnLog = writeChan logChan
            , discordOnEvent = liftIO . writeChan eventChan
            , discordOnEnd = pure ()
            , discordGatewayIntent
            , discordForkThreadForEvents = False
            , discordEnableCache = False
            }
