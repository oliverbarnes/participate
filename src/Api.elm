module Api exposing (facebookAuthUrl, Msg(..), Me, authenticateCmd, getMeCmd, createProposalCmd)

import Http
import Task exposing (Task)
import Json.Decode as Decode
import Json.Decode exposing (Decoder)
import Json.Encode as Encode


type Msg
  = GotAccessToken String
  | AuthFailed Http.Error
  | ProposalCreated String Proposal
  | ProposalCreationFailed Http.Error
  | GotMe Me


type alias Me =
  { name : String
  }

type alias Proposal =
  { title : String
  , body : String
  }



-- ENDPOINTS


apiUrl : String
apiUrl = "http://localhost:4000"


tokenEndpoint : String
tokenEndpoint = apiUrl ++ "/token"


meEndpoint : String
meEndpoint = apiUrl ++ "/me"

newProposalEndpoint : String
newProposalEndpoint = apiUrl ++ "/proposals"


-- TODO: move client_id and redirect_uri into environment variables
facebookAuthUrl : String
facebookAuthUrl = "https://www.facebook.com/dialog/oauth?client_id=1583083701926004&redirect_uri=http://localhost:3000/facebook_redirect"



-- DECODERS & ENCODERS


decodeToken : Decoder String
decodeToken =
  Decode.at ["access_token"] Decode.string
  

decodeMe : Decoder Me
decodeMe =
  Decode.object1 Me
    (Decode.at ["data", "attributes", "name"] Decode.string)


decodeProposal : Decoder (String, Proposal)
decodeProposal =
  Decode.object2 (,)
  ( Decode.at ["data", "id"] Decode.string )
    ( Decode.object2 Proposal
        (Decode.at ["data", "attributes", "title"] Decode.string)
        (Decode.at ["data", "attributes", "body"] Decode.string)
    )


encodeProposal : Proposal -> String
encodeProposal proposal =
  -- http://noredink.github.io/json-to-elm/
  Encode.object
    [ ( "data"
      , Encode.object
          [ ( "type", Encode.string "proposal" )
          , ( "attributes"
            , Encode.object
              [ ( "title", Encode.string proposal.title )
              , ( "body", Encode.string proposal.body )
              ]
            )
          ]
      )
    ] 
    |> Encode.encode 0



-- COMMANDS


authenticateCmd : String -> (Msg -> a) -> Cmd a
authenticateCmd authCode wrapMsg =
  let
    body =
      "{\"auth_code\": \"" ++ authCode ++ "\"}"
    
    requestTask =
      exchangeAuthCodeForToken body
  in
    Task.perform AuthFailed GotAccessToken requestTask
      |> Cmd.map wrapMsg


getMeCmd : String -> (Msg -> a) -> Cmd a
getMeCmd accessToken wrapMsg =
  getWithToken meEndpoint accessToken decodeMe
    |> Task.perform AuthFailed GotMe
    |> Cmd.map wrapMsg


createProposalCmd : Proposal -> String -> (Msg -> a) -> Cmd a
createProposalCmd proposal accessToken wrapMsg =
  postProposal proposal accessToken
    |> Task.perform ProposalCreationFailed (uncurry ProposalCreated)
    |> Cmd.map wrapMsg



-- HTTP requests


exchangeAuthCodeForToken : String -> Task Http.Error String
exchangeAuthCodeForToken body =
  { verb = "POST", headers = [("Content-Type", "application/json")], url = tokenEndpoint, body = Http.string body }
    |> Http.send Http.defaultSettings
    |> Http.fromJson decodeToken


postProposal : Proposal -> String -> Task Http.Error (String, Proposal)
postProposal proposal accessToken =
  { verb = "POST"
  , headers =
      [ ("Authorization", "Bearer " ++ accessToken)
      , ("Content-Type", "application/vnd.api+json")
      ]
  , url = newProposalEndpoint
  , body = Http.string (encodeProposal proposal)
  }
    |> Http.send Http.defaultSettings
    |> Http.fromJson decodeProposal


getWithToken : String -> String -> Decoder a -> Task Http.Error a
getWithToken url accessToken responseDecoder  =
  { verb = "GET"
  , headers =
      [ ("Authorization", "Bearer " ++ accessToken)
      , ("Content-Type", "application/vnd.api+json")
      ]
  , url = url
  , body = Http.empty
  }
  |> Http.send Http.defaultSettings
  |> Http.fromJson responseDecoder
