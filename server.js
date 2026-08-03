require('dotenv').config();

const express = require('express');
const cors = require('cors');
const path = require('path');
const { AccessToken } = require('livekit-server-sdk');


const app = express();


app.use(cors());
app.use(express.json());



const LIVEKIT_API_KEY = process.env.LIVEKIT_API_KEY;
const LIVEKIT_API_SECRET = process.env.LIVEKIT_API_SECRET;

const PORT = process.env.PORT || 3000;

const TOKEN_TTL_SECONDS = 86400;



// Home
app.get('/', (req, res) => {

  res.json({
    status: 'ok',
    message: 'CRUX Server running',
    endpoints:[
      '/ping',
      '/livekit-token'
    ]
  });

});



// Ping
app.get('/ping',(req,res)=>{

  res.json({
    status:'ok',
    service:'crux-server'
  });

});




// LiveKit token
app.get('/livekit-token', async(req,res)=>{


  const {
    room,
    identity,
    name
  } = req.query;



  if(!room || !identity){

    return res.status(400).json({
      error:'room and identity are required'
    });

  }



  if(!LIVEKIT_API_KEY || !LIVEKIT_API_SECRET){

    return res.status(500).json({
      error:'LiveKit credentials missing'
    });

  }



  try{


    const at = new AccessToken(
      LIVEKIT_API_KEY,
      LIVEKIT_API_SECRET,
      {
        identity,
        name:name || identity,
        ttl:TOKEN_TTL_SECONDS
      }
    );



    at.addGrant({

      roomJoin:true,
      room,

      canPublish:true,
      canSubscribe:true,
      canPublishData:true

    });



    if(req.query.host === 'true'){

      at.addGrant({

        roomAdmin:true,
        roomRecord:true

      });

    }




    const token = await at.toJwt();



    res.json({

      token,
      room,
      identity

    });



  }catch(error){


    console.error(
      'LiveKit error:',
      error
    );


    res.status(500).json({

      error:'Failed generating token'

    });


  }


});





// Static web files

app.use(
  express.static(
    path.join(__dirname,'web/public')
  )
);





// Web routes

app.get('/login',(req,res)=>{

 res.sendFile(
  path.join(
    __dirname,
    'web/public/login/index.html'
  )
 );

});



app.get('/signup',(req,res)=>{

 res.sendFile(
  path.join(
    __dirname,
    'web/public/signup/index.html'
  )
 );

});



app.get('/app',(req,res)=>{

 res.sendFile(
  path.join(
    __dirname,
    'web/public/app/index.html'
  )
 );

});



app.get('/join/:id',(req,res)=>{

 res.sendFile(
  path.join(
    __dirname,
    'web/public/join/index.html'
  )
 );

});




// SPA fallback

app.get('*',(req,res)=>{

 res.sendFile(
  path.join(
    __dirname,
    'web/public/index.html'
  )
 );

});






app.listen(
 PORT,
 '0.0.0.0',
 ()=>{

 console.log(
  `CRUX Server running on port ${PORT}`
 );

});
