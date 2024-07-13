{-# LANGUAGE BlockArguments #-}

module Example where

import Prelude
import FRP.Rhine
import FRP.Rhine.Discord
import Dhall
import Discord (def, DiscordHandler)
import System.Random (StdGen, getStdGen)
import Discord.Types (Message)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text

data MessageDeletionPolicy
    = OldestFirst
    | NewestFirst
    | Random
    deriving stock (Generic)

instance FromDhall MessageDeletionPolicy
instance ToDhall MessageDeletionPolicy

data Config = Config
    { discordToken :: Text
    , messageDeletionPolicy :: MessageDeletionPolicy
    , messageHalfLifeSeconds :: Double
    }
    deriving stock (Generic)

instance FromDhall Config
instance ToDhall Config

data State = State
    { stdGen :: StdGen
    , messages :: [Message]
    }

getInitialState :: DiscordHandler State
getInitialState = do
    liftIO $ putStrLn "Initialising"
    stdGen <- getStdGen
    let messages = [] :: [Message]
    pure State{..}

handleEvents :: ClSF DiscordHandler DiscordEventClock State State
handleEvents = tagS &&& returnA >>> arrMCl \(ev, st) -> do
        liftIO . putStrLn $ "Event: " <> show ev
        pure st

handleLog :: ClSF DiscordHandler DiscordLogClock State State
handleLog = tagS &&& returnA >>> arrMCl \(lg, st) -> do
        liftIO . putStrLn $ "Log: " <> Text.unpack lg
        pure st

simRh :: Rhine DiscordHandler (HoistClock IO DiscordHandler (Millisecond 1000)) State State
simRh = returnA @@ ioClock waitClock

main :: IO ()
main = do
    config <- inputFile (auto @Config) "config.dhall"
    Text.putStrLn =<< flowDiscord config.discordToken def getInitialState handleEvents handleLog simRh
