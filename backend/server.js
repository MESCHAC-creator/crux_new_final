// backend/server.js
// CRUX LiveKit Token Server v2.1.0
// Firebase Auth + LiveKit JWT + Rate limiting

require('dotenv').config();

const express = require('express');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const admin = require('firebase-admin');
const { AccessToken } = require('livekit-server-sdk');


// ============================================================
// Firebase Admin Initialization
// ============================================================

if (!admin.apps.length) {

  if (process.env.FIREBASE_SERVICE_ACCOUNT) {

    const serviceAccount = JSON.parse(
      process.env.FIREBASE_SERVICE_ACCOUNT
    );

    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });

  } else {

    // Pour environnement Google avec ADC
    admin.initializeApp();
  }
}


// ============================================================
// Express
// ============================================================

const app = express();

app.use(express.json({
  limit: '10kb'
}));


// ============================================================
// CORS
// ============================================================

const allowedOrigins =
  (process.env.ALLOWED_ORIGINS || '')
    .split(',')
    .filter(Boolean);


app.use(
  cors({

    origin: (origin, callback) => {

      // Applications mobiles Flutter
      if (!origin) {
        return callback(null, true);
      }


      // Autoriser si aucune restriction
      if (!allowedOrigins.length) {
        return callback(null, true);
      }


      const allowed =
        allowedOrigins.some(
          item =>
            origin.startsWith(
              item.replace('/*', '')
            )
        );


      if (allowed) {
        return callback(null, true);
      }


      return callback(
        new Error(
          `CORS blocked: ${origin}`
        )
      );
    },


    methods:[
      'GET',
      'OPTIONS'
    ],


    allowedHeaders:[
      'Authorization',
      'Content-Type'
    ]
  })
);


// ============================================================
// Configuration
// ============================================================

const LIVEKIT_API_KEY =
  process.env.LIVEKIT_API_KEY;


const LIVEKIT_API_SECRET =
  process.env.LIVEKIT_API_SECRET;


const PORT =
  process.env.PORT || 3000;


const TOKEN_TTL_SECONDS =
  Number(
    process.env.TOKEN_TTL_SECONDS || 86400
  );



if(
 !LIVEKIT_API_KEY ||
 !LIVEKIT_API_SECRET
){

 console.error(
  'LIVEKIT_API_KEY ou LIVEKIT_API_SECRET manquant'
 );

 process.exit(1);

}



// ============================================================
// Rate limiting
// ============================================================


app.use(
 rateLimit({

  windowMs:60000,

  max:100,

  standardHeaders:true,

  legacyHeaders:false

 })
);



const tokenLimiter =
rateLimit({

 windowMs:60000,

 max:30,

 standardHeaders:true,

 legacyHeaders:false,


 keyGenerator:(req)=>{

   return req.user?.uid || req.ip;

 }

});



// ============================================================
// Firebase Authentication Middleware
// ============================================================


async function verifyFirebaseToken(
 req,
 res,
 next
){

 const header =
   req.headers.authorization;


 if(
  !header ||
  !header.startsWith('Bearer ')
 ){

  return res.status(401).json({

   error:
   'Authentification Firebase requise'

  });

 }



 const token =
   header.substring(7);



 try{


  const decoded =
   await admin
   .auth()
   .verifyIdToken(
     token,
     true
   );


  req.user = decoded;


  next();



 }catch(error){


  console.error(
   'Firebase auth error:',
   error.code
  );


  return res.status(401).json({

   error:
   'Token Firebase invalide'

  });


 }

}



// ============================================================
// Health
// ============================================================


app.get('/',(req,res)=>{


 res.json({

  status:'ok',

  service:
  'CRUX LiveKit Token Server',

  version:'2.1.0',


  endpoints:{


   health:
   'GET /',


   ping:
   'GET /ping',


   token:
   'GET /livekit-token'

  }

 });


});



app.get('/ping',(req,res)=>{

 res.json({

  status:'ok',

  timestamp:
  Date.now()

 });

});




// ============================================================
// LiveKit Token Generator
// ============================================================


app.get(
'/livekit-token',
verifyFirebaseToken,
tokenLimiter,


async(req,res)=>{


 try{


 const {
   room,
   identity,
   name,
   isHost
 }
 =
 req.query;



 if(
  !room ||
  !identity ||
  !name
 ){

 return res.status(400).json({

  error:
  'Paramètres manquants',

  required:[
   'room',
   'identity',
   'name'
  ]

 });

 }



 if(
  room.length>100 ||
  identity.length>100 ||
  name.length>100
 ){

 return res.status(400).json({

  error:
  'Paramètres trop longs'

 });

 }




 // Sécurité UID Firebase

 if(
   identity !== req.user.uid
 ){

 return res.status(403).json({

  error:
  'Identité non autorisée'

 });

 }



 const host =
   isHost === 'true';



 const accessToken =
 new AccessToken(

  LIVEKIT_API_KEY,

  LIVEKIT_API_SECRET,

  {


   identity:


    identity,


   name:


    name,


   ttl:


    TOKEN_TTL_SECONDS


  }

 );




 accessToken.addGrant({

  roomJoin:true,

  room:


    room,


  canPublish:true,


  canSubscribe:true,


  canPublishData:true,


  canUpdateOwnMetadata:true,


  // permissions host

  roomAdmin:
    host,


  roomRecord:
    host


 });



 const token =
 await accessToken.toJwt();



 console.log(
  `Token généré user=${identity} room=${room} host=${host}`
 );



 return res.json({

  token,


  room,


  identity,


  isHost:host,


  expiresIn:
  TOKEN_TTL_SECONDS


 });



 }catch(error){


 console.error(
  'Token error:',
  error
 );


 return res.status(500).json({

  error:
  'Erreur génération token'

 });


 }


});




// ============================================================
// 404
// ============================================================


app.use((req,res)=>{

 res.status(404).json({

  error:
  'Route introuvable'

 });

});



// ============================================================
// Start
// ============================================================


app.listen(
 PORT,
 ()=>{

 console.log(
 `🚀 CRUX LiveKit Token Server v2.1.0 port ${PORT}`
 );


 console.log(
 'Firebase Auth : ON'
 );


 console.log(
 'LiveKit JWT : ON'
 );


}
);
