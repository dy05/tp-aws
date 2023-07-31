const fs = require('fs');
const AWS = require('aws-sdk');

const dynamoDB = new AWS.DynamoDB.DocumentClient();

exports.handler = async (event) => {
  try {
    const params = {
      TableName: 'JOBS',
      ScanIndexForward: false,
      Limit: 1
    };

    const result = await dynamoDB.scan(params).promise();
    const latestItem = result.Items[0];
    const jobType = latestItem.job_type;
    const content = latestItem.content;
    let response = null;

    if (jobType === 'addToDynamoDB') {
      console.log('Le dernier élément a un job_type "addToDynamoDB"');

      const params = {
        TableName: 'addToDynamos',
        Item:{
          id: latestItem.id,
          content: content
        }
      };

      try {
        await dynamoDB.put(params).promise();

        console.log('Élément ajouté avec succès à la table DynamoDB');
        response = {
          statusCode: 200,
          body: JSON.stringify('OK')
        };
      } catch (error) {
        console.error("Erreur lors de l'ajout de l'élément à la table DynamoDB", error);
        response = {
          statusCode: 500,
          body: JSON.stringify("Erreur lors de l'ajout de l'élément à la table DynamoDB")
        };
      }
    } else if (jobType === 'addToS3') {
      const s3 = new AWS.S3();
      let fileName = (new Date()).getTime() + '.txt';
      let bufferData = Buffer.from(content, 'utf8');

      s3.upload({
        Bucket: 'myterras3appbucket',
        Body: bufferData,
        Key: fileName,
      }, function(err, data) {
        if (err) {
          console.error("Erreur lors de l'upload: " + err.message);
          throw err;
        }

        response = {
          statusCode: 200,
          body: 'Upload effectué avec succès: ' + (JSON.stringify(data)),
        };
      });
    }
    return response;
  } catch (error) {
    console.error('Erreur lors du contrôle :', error);

    return {
      statusCode: 500,
      body: 'Erreur lors du contrôle'
    };
  }
};

async function createFile(content) {
  let fileName = (new Date()).getTime() + '.txt';
  await fs.writeFileSync(fileName, content, err => {
    if (err) {
      console.error(err.message);
      throw err;
    }
  });

  return Promise.resolve({name: fileName});
}
