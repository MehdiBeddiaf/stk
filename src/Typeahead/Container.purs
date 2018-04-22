module Typeahead.Container where

import Prelude

import Control.Monad.Aff.Class (class MonadAff)
import Control.Monad.Aff.Console (log)
import Control.Monad.Eff.Console (CONSOLE)
import Control.Monad.Eff.Timer (TIMER)
import Control.Monad.Except (runExcept)

import Data.Either (Either(..))
import Data.Foreign (ForeignError)
import Data.Foreign.Class (decode)
import Data.Foreign.Generic (decodeJSON)
import Data.List.NonEmpty (NonEmptyList)
import Data.Maybe (Maybe(..))
import Data.Traversable (traverse)

import Halogen as H
import Halogen.ECharts as EC
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP

import Helpers (class_)
import Models (Symbol(..))
import Network.HTTP.Affjax as AX

import Type.Data.Boolean (kind Boolean)
import Typeahead.Component as Typeahead

type Symbols = Array Symbol

type State =
  { loading :: Boolean
  , result :: Maybe Symbols
  }

type Input = Unit
data Message = Selected String

data Query a
  = Initialize a
  | Finalize a
  | HandleSelection Typeahead.Message a
  | GetState (Boolean -> a)

type Component m = H.Component HH.HTML Query Unit Message m
type DSL q m = H.ParentDSL State Query q Unit Message m
type HTML q m = H.ParentHTML Query q Unit m

type Effects eff = EC.EChartsEffects ( console :: CONSOLE, ajax :: AX.AJAX, timer :: TIMER | eff )

component :: ∀ eff m. MonadAff ( Effects eff ) m => Component m
component =
    H.lifecycleParentComponent
    { initialState: const initialState
    , render
    , eval
    , initializer: Just (H.action Initialize)
    , finalizer: Just (H.action Finalize)
    , receiver: const Nothing
    }
  where
    initialState :: State
    initialState = { loading: false, result: Nothing }

    eval :: Query ~> DSL Typeahead.Query m
    eval = case _ of
      Initialize next -> do
        H.liftAff $ log "Fetching MostActive data on mount"
        H.modify (_ { loading = true })
        response <- H.liftAff $ AX.get "https://api.iextrading.com/1.0/ref-data/symbols"
        let parsedResponse = handleResponse $ runExcept $ traverse decode =<< decodeJSON response.response
        H.modify (_ { loading = false, result = parsedResponse })
        pure next
      Finalize next -> do
        pure next
      HandleSelection (Typeahead.Selected item) next -> do
        H.liftAff $ log $ "Selected item from child " <> item
        H.raise $ Selected item
        pure next
      GetState reply -> do
        state <- H.get
        pure (reply state.loading)

    render :: State -> HTML Typeahead.Query m
    render st =
      HH.div_
      [HH.section
        [ class_ "hero" ]
        [ HH.div
          [ class_ "hero-body" ]
          [ HH.div
              [ class_ "container" ]
              [ HH.form_ $
                [ HH.div_
                    case st.result of
                      Nothing ->
                        [ HH.div
                          [ class_ "columns is-mobile" ]
                          [ HH.div
                            [ class_ "column is-half is-offset-one-quarter" ]
                            [ HH.div
                              [ class_ "field" ]
                              [ HH.div
                                [ class_ "control is-loading is-medium"]
                                [ HH.input
                                  [ class_ "input is-medium",
                                    HP.placeholder "Loading stock symbols...",
                                    HP.disabled true
                                  ]
                                ]
                              ]
                            ]
                          ]
                        ]
                      Just symbols ->
                        let config = { items: (map (\(Symbol { symbol, name }) -> symbol <> " - " <> name) symbols)
                                     , keepOpen: false
                                     }
                        in [HH.slot unit Typeahead.component config (HE.input HandleSelection)]
                ]
              ]
          ]
        ]
      ]

handleResponse :: Either (NonEmptyList ForeignError) Symbols -> Maybe Symbols
handleResponse r = do
  case r of
    Left err -> Nothing
    Right something -> Just something