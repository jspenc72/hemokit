{-# LANGUAGE NamedFieldPuns #-}

-- | Some convenience for building applications that want to read Emotiv data.
--
-- You can use this if you are writing an EEG application and don't want to do
-- the whole device selection / opening yourself.
module Hemokit.Start
  ( EmotivArgs (..)
  , emotivArgsParser
  , parseModel
  , parseArgs
  , getEmotivDeviceFromArgs
  ) where

import           Options.Applicative
import           System.IO (stdin)

import           Hemokit hiding (serial)


-- | Commonly used options for EEG command line applications.
-- Mainly deals with input selection.
data EmotivArgs = EmotivArgs
  { model       :: EmotivModel        -- ^ What model to use for decryption.
  , serial      :: Maybe SerialNumber -- ^ What serial to use for decryption.
                                      --   Also allows to pick a certain device.
  , fromFile    :: Maybe FilePath     -- ^ Use the given device or dump file for input.
                                      --   If not given, HIDAPI is used.
  } deriving (Eq, Ord, Show)


-- | EEG model command line parser.
parseModel :: Monad m => String -> m EmotivModel
parseModel s = case s of
  "consumer"  -> return Consumer
  "developer" -> return Developer
  _           -> fail "Model is not valid. Must be 'consumer' or 'developer'."


-- | Command line parser for EEG selection. See `EmotivArgs`.
emotivArgsParser :: Parser EmotivArgs
emotivArgsParser = EmotivArgs
  <$> option (eitherReader parseModel)
      ( long "model" <> metavar "MODEL"
        <> value Consumer
        <> help "Consumer or Developer model, Consumer by default" )
  <*> (optional . option (maybeReader makeSerialNumberFromString "Serial number of has invalid format"))
      ( long "serial" <> metavar "SERIALNUMBER"
        <> help "The serial to use. If no --from-file is given, this will select the device" )
  <*> (optional . strOption)
      ( long "from-file" <> metavar "PATH"
        <> help "The file path to read from (e.g. /dev/hidraw0 or myfile.dump)" )
  where
    maybeReader :: (String -> Maybe a) -> String -> ReadM a
    maybeReader mbFn msg = eitherReader (maybe (fail msg) pure . mbFn)


-- | Runs a command line parser. The given program description is used for the
-- --help message.
parseArgs :: String -> Parser a -> IO a
parseArgs programDescription parser = execParser $ info (helper <*> parser)
                                                        (progDesc programDescription)


-- | Depending on some common EEG-choice-related user input, list devices or
-- try to open the correct device.
getEmotivDeviceFromArgs :: EmotivArgs -> IO (Either String EmotivDevice)
getEmotivDeviceFromArgs EmotivArgs{ model, serial, fromFile } = case fromFile of

    -- File given, use device file / file handle
    Just f | Just s <- serial -> Right <$> if f == "-" then openEmotivDeviceHandle model s stdin
                                                       else openEmotivDeviceFile   model s f
           | otherwise        -> fail "A serial number must be provided when using --from-file"

    -- No file given, use HIDAPI to select the device
    Nothing -> do
      devices <- getEmotivDevices

      case devices of
        [] -> fail "No devices found."
        _  -> case serial of

          -- Pick the last device with the serial the user wants
          Just s -> case reverse [ d | d <- devices, deviceInfoSerial d == Just s ] of
                      []  -> fail $ "No device with serial " ++ show s
                      d:_ -> print d >> Right <$> openEmotivDevice model d

          -- TODO Do smarter auto detection, e.g. filter for Emotiv vendorIDs
          --      or the "EPOC BCI" product string.
          -- The user selected no serial, we just use the last device
          _      -> print (last devices) >> Right <$> openEmotivDevice model (last devices)
